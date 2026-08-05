// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpikoAccount} from "../../../src/contracts/adapters/ll-adapter/SpikoAccount.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";

import {IOracle} from "../../../src/interfaces/adapters/ll-adapter/IOracle.sol";
import {ISpikoAccount} from "../../../src/interfaces/adapters/ll-adapter/spiko/ISpikoAccount.sol";
import {ISpikoRedemption} from "../../../src/interfaces/adapters/ll-adapter/spiko/ISpikoRedemption.sol";

import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {ERC1363} from "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Test} from "forge-std/Test.sol";

contract SpikoAccountTest is Test {
    uint256 internal constant TOKEN_AMOUNT = 100e5;
    uint256 internal constant REQUEST_ASSETS = 102e6;
    uint48 internal constant SETTLEMENT_DURATION = 30 days;

    MockSpikoToken internal token;
    MockSpikoAsset internal asset;
    MockSpikoOracle internal oracle;
    MockSpikoRedemption internal redemption;
    MockSpikoVault internal vault;
    MockSpikoCowSettlement internal cowSwapSettlement;
    MigratablesFactory internal factory;
    SpikoAccount internal implementation;
    SpikoAccount internal account;

    address internal recipient = makeAddr("recipient");

    function setUp() public {
        token = new MockSpikoToken();
        asset = new MockSpikoAsset();
        oracle = new MockSpikoOracle(1.02e18);
        redemption = new MockSpikoRedemption(token, asset);
        vault = new MockSpikoVault(address(asset));
        cowSwapSettlement = new MockSpikoCowSettlement(makeAddr("cowVaultRelayer"));
        factory = new MigratablesFactory(address(this));
        implementation = _newImplementation();

        factory.whitelist(address(implementation));
        account = SpikoAccount(factory.create(1, address(this), abi.encode(address(vault), address(this))));
    }

    function testDisabledUsdcOutputLeavesSpkccHeldWithoutReadingOracle() public {
        oracle.setShouldRevert(true);
        token.mint(address(account), TOKEN_AMOUNT);

        account.sync();

        assertEq(token.balanceOf(address(account)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(address(redemption)), 0);
        assertEq(account.pendingId(), bytes32(0));
        assertEq(account.requestNonce(), 0);
    }

    function testBelowMinimumLeavesSpkccHeldWithoutReadingOracle() public {
        redemption.setOutputEnabled(true);
        redemption.setMinimum(TOKEN_AMOUNT + 1);
        oracle.setShouldRevert(true);
        token.mint(address(account), TOKEN_AMOUNT);

        account.sync();

        assertEq(token.balanceOf(address(account)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(address(redemption)), 0);
        assertEq(account.pendingId(), bytes32(0));
    }

    function testEnabledRouteCreatesExactUsdcRequestAndFreezesValue() public {
        bytes32 id = _request(TOKEN_AMOUNT);
        bytes32 salt = account.pendingSalt();
        bytes32 expectedId =
            keccak256(abi.encodePacked(address(account), address(token), address(asset), TOKEN_AMOUNT, salt));
        (ISpikoRedemption.Status status, uint48 issuerDeadline) = redemption.details(id);

        assertEq(id, expectedId);
        assertEq(id, redemption.lastId());
        assertEq(redemption.lastUser(), address(account));
        assertEq(redemption.lastOutput(), address(asset));
        assertEq(redemption.lastInputValue(), TOKEN_AMOUNT);
        assertEq(redemption.lastSalt(), salt);
        assertEq(uint8(status), uint8(ISpikoRedemption.Status.PENDING));
        assertGt(issuerDeadline, block.timestamp);
        assertEq(account.pendingTokenAmount(), TOKEN_AMOUNT);
        assertEq(account.pendingAssets(), REQUEST_ASSETS);
        assertEq(account.pendingExpiry(), issuerDeadline + SETTLEMENT_DURATION);
        assertEq(account.requestNonce(), 1);
        assertEq(token.balanceOf(address(account)), 0);
        assertEq(token.balanceOf(address(redemption)), TOKEN_AMOUNT);
        assertEq(account.totalAssets(), REQUEST_ASSETS);
    }

    function testExcessiveIssuerDeadlineRollsBackRequest() public {
        redemption.setOutputEnabled(true);
        redemption.setDelay(14 days + 1);
        token.mint(address(account), TOKEN_AMOUNT);

        vm.expectRevert(ISpikoAccount.InvalidRedemptionRequest.selector);
        account.sync();

        assertEq(token.balanceOf(address(account)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(address(redemption)), 0);
        assertEq(account.pendingId(), bytes32(0));
        assertEq(account.requestNonce(), 0);
    }

    function testSettlementIsNotDoubleCountedAcrossSyncAndAdapterPull() public {
        _request(TOKEN_AMOUNT);
        asset.mint(address(account), 40e6);

        assertEq(account.totalAssets(), REQUEST_ASSETS);

        account.sync();

        assertEq(account.pendingAssets(), 62e6);
        assertEq(asset.allowance(address(account), address(this)), 40e6);
        assertEq(account.totalAssets(), REQUEST_ASSETS);

        asset.transferFrom(address(account), recipient, 40e6);

        assertEq(asset.balanceOf(address(account)), 0);
        assertEq(asset.allowance(address(account), address(this)), 0);
        assertEq(account.totalAssets(), 62e6);

        asset.mint(address(account), 20e6);
        assertEq(account.totalAssets(), 62e6);

        account.sync();

        assertEq(account.pendingAssets(), 42e6);
        assertEq(asset.allowance(address(account), address(this)), 20e6);
        assertEq(account.totalAssets(), 62e6);
    }

    function testExecutedFullSettlementClearsAndSubmitsQueuedSpkcc() public {
        bytes32 firstId = _request(TOKEN_AMOUNT);
        bytes32 firstSalt = account.pendingSalt();
        token.mint(address(account), 50e5);
        asset.mint(address(account), REQUEST_ASSETS);
        redemption.execute(firstId);

        account.sync();

        bytes32 secondId = account.pendingId();
        assertNotEq(secondId, bytes32(0));
        assertNotEq(secondId, firstId);
        assertNotEq(account.pendingSalt(), firstSalt);
        assertEq(account.pendingTokenAmount(), 50e5);
        assertEq(account.pendingAssets(), 51e6);
        assertEq(account.requestNonce(), 2);
        assertEq(token.balanceOf(address(account)), 0);
        assertEq(asset.allowance(address(account), address(this)), REQUEST_ASSETS);
        assertEq(account.totalAssets(), 153e6);
    }

    function testIssuerExpiredPendingRequestCancelsWithoutSameSyncResubmission() public {
        bytes32 id = _request(TOKEN_AMOUNT);
        (, uint48 issuerDeadline) = redemption.details(id);
        vm.warp(issuerDeadline);

        account.sync();

        (ISpikoRedemption.Status status,) = redemption.details(id);
        assertEq(uint8(status), uint8(ISpikoRedemption.Status.CANCELED));
        assertEq(account.pendingId(), bytes32(0));
        assertEq(account.pendingAssets(), 0);
        assertEq(token.balanceOf(address(account)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(address(redemption)), 0);
        assertEq(account.requestNonce(), 1);
        assertTrue(account.redemptionPaused());
        assertEq(account.totalAssets(), REQUEST_ASSETS);
    }

    function testOnlyOwnerCanRearmAfterCancellation() public {
        bytes32 id = _request(TOKEN_AMOUNT);
        (, uint48 issuerDeadline) = redemption.details(id);
        vm.warp(issuerDeadline);
        account.sync();

        vm.prank(makeAddr("keeper"));
        account.sync();

        assertTrue(account.redemptionPaused());
        assertEq(account.pendingId(), bytes32(0));
        assertEq(account.requestNonce(), 1);
        assertEq(token.balanceOf(address(account)), TOKEN_AMOUNT);

        account.sync();

        assertFalse(account.redemptionPaused());
        assertNotEq(account.pendingId(), bytes32(0));
        assertEq(account.requestNonce(), 2);
        assertEq(token.balanceOf(address(account)), 0);
    }

    function testExternalCancellationDoesNotDoubleCountRefundBeforeSync() public {
        bytes32 id = _request(TOKEN_AMOUNT);
        bytes32 salt = account.pendingSalt();
        (, uint48 issuerDeadline) = redemption.details(id);
        vm.warp(issuerDeadline);

        redemption.cancelRedemption(address(account), IERC20(address(token)), address(asset), TOKEN_AMOUNT, salt);

        assertEq(account.pendingId(), id);
        assertEq(token.balanceOf(address(account)), TOKEN_AMOUNT);
        assertEq(account.totalAssets(), REQUEST_ASSETS);

        account.sync();

        assertEq(account.pendingId(), bytes32(0));
        assertEq(account.totalAssets(), REQUEST_ASSETS);
    }

    function testPendingRequestRemainsValuedPastProtocolExpiryUntilCanceled() public {
        bytes32 id = _request(TOKEN_AMOUNT);
        vm.warp(account.pendingExpiry());

        (ISpikoRedemption.Status status,) = redemption.details(id);
        assertEq(uint8(status), uint8(ISpikoRedemption.Status.PENDING));
        assertEq(account.totalAssets(), REQUEST_ASSETS);

        account.sync();

        assertEq(account.pendingId(), bytes32(0));
        assertEq(token.balanceOf(address(account)), TOKEN_AMOUNT);
        assertEq(account.totalAssets(), REQUEST_ASSETS);
    }

    function testExecutedUnpaidResidualWritesOffOnlyAfterProtocolExpiry() public {
        bytes32 id = _request(TOKEN_AMOUNT);
        redemption.execute(id);
        asset.mint(address(account), 40e6);
        account.sync();
        token.mint(address(account), 50e5);

        assertEq(account.pendingAssets(), 62e6);
        assertEq(account.totalAssets(), 153e6);

        vm.warp(account.pendingExpiry() - 1);
        account.sync();
        assertEq(account.pendingId(), id);
        assertEq(account.pendingAssets(), 62e6);

        vm.warp(account.pendingExpiry());
        assertEq(account.totalAssets(), 91e6);

        account.sync();

        assertEq(account.pendingId(), bytes32(0));
        assertEq(account.pendingAssets(), 0);
        assertTrue(account.redemptionPaused());
        assertEq(token.balanceOf(address(account)), 50e5);
        assertEq(asset.balanceOf(address(account)), 40e6);
        assertEq(account.totalAssets(), 91e6);
    }

    function _request(uint256 amount) internal returns (bytes32 id) {
        redemption.setOutputEnabled(true);
        token.mint(address(account), amount);
        account.sync();
        id = account.pendingId();
        assertNotEq(id, bytes32(0));
    }

    function _newImplementation() internal returns (SpikoAccount) {
        return new SpikoAccount(
            address(oracle),
            address(factory),
            address(token),
            address(redemption),
            address(asset),
            SETTLEMENT_DURATION,
            address(cowSwapSettlement)
        );
    }
}

contract MockSpikoToken is ERC1363 {
    constructor() ERC20("Spiko Cash and Carry", "SPKCC") {}

    function decimals() public pure override returns (uint8) {
        return 5;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

contract MockSpikoAsset is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockSpikoOracle is IOracle {
    uint256 internal _price;
    bool internal _shouldRevert;

    constructor(uint256 price_) {
        _price = price_;
    }

    function setShouldRevert(bool shouldRevert_) external {
        _shouldRevert = shouldRevert_;
    }

    function getPrice() external view returns (uint256 price) {
        if (_shouldRevert) {
            revert InvalidPrice();
        }
        return _price;
    }
}

contract MockSpikoVault {
    address internal immutable _asset;

    constructor(address asset_) {
        _asset = asset_;
    }

    function asset() external view returns (address) {
        return _asset;
    }
}

contract MockSpikoCowSettlement {
    address public immutable vaultRelayer;

    constructor(address vaultRelayer_) {
        vaultRelayer = vaultRelayer_;
    }
}

contract MockSpikoRedemption is ISpikoRedemption, IERC1363Receiver {
    struct Details {
        Status status;
        uint48 deadline;
        uint256 inputValue;
    }

    MockSpikoToken internal immutable _input;
    MockSpikoAsset internal immutable _output;

    mapping(bytes32 id => Details data) internal _details;

    bool internal _outputEnabled;
    uint256 internal _minimum;
    uint48 internal _delay = 14 days;

    bytes32 public lastId;
    address public lastUser;
    address public lastOutput;
    uint256 public lastInputValue;
    bytes32 public lastSalt;

    constructor(MockSpikoToken input_, MockSpikoAsset output_) {
        _input = input_;
        _output = output_;
    }

    function setOutputEnabled(bool enabled) external {
        _outputEnabled = enabled;
    }

    function setMinimum(uint256 minimum_) external {
        _minimum = minimum_;
    }

    function setDelay(uint48 delay_) external {
        _delay = delay_;
    }

    function execute(bytes32 id) external {
        Details storage data = _details[id];
        require(data.status == Status.PENDING);
        data.status = Status.EXECUTED;
        _input.burn(address(this), data.inputValue);
    }

    function outputsFor(IERC20 input) external view returns (address[] memory outputs) {
        require(address(input) == address(_input));
        outputs = new address[](_outputEnabled ? 2 : 1);
        outputs[0] = address(0);
        if (_outputEnabled) {
            outputs[1] = address(_output);
        }
    }

    function minimum(IERC20 input) external view returns (uint256) {
        require(address(input) == address(_input));
        return _minimum;
    }

    function details(bytes32 id) external view returns (Status status, uint48 deadline) {
        Details memory data = _details[id];
        return (data.status, data.deadline);
    }

    function hashRedemptionId(address user, IERC20 input, address output, uint256 inputValue, bytes32 salt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(user, input, output, inputValue, salt));
    }

    function cancelRedemption(address user, IERC20 input, address output, uint256 inputValue, bytes32 salt) external {
        bytes32 id = hashRedemptionId(user, input, output, inputValue, salt);
        Details storage data = _details[id];
        require(data.status == Status.PENDING);
        require(data.deadline <= block.timestamp);
        data.status = Status.CANCELED;
        input.transfer(user, inputValue);
    }

    function onTransferReceived(address user, address, uint256 value, bytes calldata data) external returns (bytes4) {
        require(msg.sender == address(_input));
        (address output, bytes32 salt) = abi.decode(data, (address, bytes32));
        require(_outputEnabled && output == address(_output));
        require(value >= _minimum);

        bytes32 id = hashRedemptionId(user, IERC20(msg.sender), output, value, salt);
        require(_details[id].status == Status.NULL);
        _details[id] = Details({status: Status.PENDING, deadline: uint48(block.timestamp) + _delay, inputValue: value});
        lastId = id;
        lastUser = user;
        lastOutput = output;
        lastInputValue = value;
        lastSalt = salt;
        return IERC1363Receiver.onTransferReceived.selector;
    }
}

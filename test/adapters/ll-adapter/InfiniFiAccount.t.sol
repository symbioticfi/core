// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {InfiniFiAccount} from "../../../src/contracts/adapters/ll-adapter/InfiniFiAccount.sol";
import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {liUSD13w_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/liUSD13w_Account.sol";
import {liUSD4w_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/liUSD4w_Account.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IInfiniFiAccount} from "../../../src/interfaces/adapters/ll-adapter/infinifi/IInfiniFiAccount.sol";
import {IInfiniFiGateway} from "../../../src/interfaces/adapters/ll-adapter/infinifi/IInfiniFiGateway.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InfiniFiAccountTest is Test {
    uint48 internal constant COOLDOWN = 3 days;
    uint32 internal constant UNWINDING_EPOCHS = 4;
    uint256 internal constant UNWINDING_DURATION = 28 days;

    address internal adapter = makeAddr("adapter");
    address internal cowSettlement = makeAddr("cowSettlement");
    address internal cowRelayer = makeAddr("cowRelayer");

    MockERC20 internal usdc;
    MockERC20 internal liusd;
    MockERC20 internal iusd;
    MockInfiniFiUnwindingModule internal unwindingModule;
    MockInfiniFiRedeemController internal redeemController;
    MockInfiniFiGateway internal gateway;
    MockOracle internal oracle;
    InfiniFiAccount internal account;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        liusd = new MockERC20("Locked iUSD - 4 weeks", "liUSD-4w", 18);
        iusd = new MockERC20("infiniFi USD", "iUSD", 18);
        unwindingModule = new MockInfiniFiUnwindingModule(iusd);
        redeemController = new MockInfiniFiRedeemController(usdc, iusd);
        gateway = new MockInfiniFiGateway(liusd, iusd, unwindingModule, redeemController, UNWINDING_DURATION);
        oracle = new MockOracle(1e18);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        vm.mockCall(cowSettlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(cowRelayer));
        InfiniFiAccount implementation = new InfiniFiAccount(
            address(oracle),
            address(factory),
            COOLDOWN,
            address(liusd),
            address(gateway),
            address(unwindingModule),
            address(redeemController),
            address(iusd),
            UNWINDING_EPOCHS,
            cowSettlement
        );
        factory.whitelist(address(implementation));
        account = InfiniFiAccount(
            factory.create(1, address(this), abi.encode(address(new MockVault(address(usdc))), adapter))
        );
    }

    function testRejectsVaultAssetMismatch() public {
        MockERC20 wrongAsset = new MockERC20("Wrong USD", "wUSD", 6);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        InfiniFiAccount implementation = new InfiniFiAccount(
            address(oracle),
            address(factory),
            COOLDOWN,
            address(liusd),
            address(gateway),
            address(unwindingModule),
            address(redeemController),
            address(iusd),
            UNWINDING_EPOCHS,
            cowSettlement
        );
        factory.whitelist(address(implementation));
        bytes memory data = abi.encode(address(new MockVault(address(wrongAsset))), adapter);

        vm.expectRevert(IInfiniFiAccount.InvalidAsset.selector);
        factory.create(1, address(this), data);
    }

    function testRequestStartsUnwindingAndRecordsTimestampOnce() public {
        uint256 ts = vm.getBlockTimestamp();
        liusd.mint(address(account), 100e18);

        vm.expectCall(
            address(gateway), abi.encodeWithSelector(IInfiniFiGateway.startUnwinding.selector, 100e18, UNWINDING_EPOCHS)
        );
        account.sync();

        assertEq(liusd.balanceOf(address(account)), 0);
        assertEq(account.unwindingTimestamps(0), ts);
        assertEq(unwindingModule.balanceOf(address(account), ts), 100e18);
        assertEq(account.totalAssets(), 100e6);

        // a second owner sync in the same second skips the request: the unwinding position key
        // is keccak(account, block.timestamp), so a second start would collide and revert
        liusd.mint(address(account), 50e18);
        account.sync();

        assertEq(liusd.balanceOf(address(account)), 50e18);
        vm.expectRevert();
        account.unwindingTimestamps(1);
        assertEq(account.totalAssets(), 150e6);

        // a later sync picks the held balance up under a new position
        vm.warp(ts + 1);
        account.sync();

        assertEq(liusd.balanceOf(address(account)), 0);
        assertEq(account.unwindingTimestamps(1), ts + 1);
        assertEq(account.totalAssets(), 150e6);
    }

    function testPermissionlessSyncRespectsCooldown() public {
        address keeper = makeAddr("keeper");

        liusd.mint(address(account), 1e18);
        vm.prank(keeper);
        account.sync();

        assertEq(liusd.balanceOf(address(account)), 0);

        liusd.mint(address(account), 1e18);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(keeper);
        account.sync();

        assertEq(liusd.balanceOf(address(account)), 1e18);

        vm.warp(vm.getBlockTimestamp() + COOLDOWN);
        vm.prank(keeper);
        account.sync();

        assertEq(liusd.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 2e6);
    }

    function testLiveValuationTracksExchangeRateAndUnwindingBalance() public {
        uint256 ts = vm.getBlockTimestamp();
        oracle.setPrice(1.2e18);
        gateway.setExchangeRate(1.2e18);
        liusd.mint(address(account), 100e18);

        // pre-request the held liUSD is priced by the bucket oracle
        assertEq(account.totalAssets(), 120e6);

        // valuation is continuous across the request: the position opens at the exchange rate
        account.sync();
        assertEq(account.totalAssets(), 120e6);

        // the unwinding position keeps earning during unwinding
        unwindingModule.setBalance(address(account), ts, 121e18);
        assertEq(account.totalAssets(), 121e6);

        // slashing is reflected through the live unwinding balance
        unwindingModule.setBalance(address(account), ts, 60e18);
        assertEq(account.totalAssets(), 60e6);
    }

    function testMaturityWithdrawsAndRedeemsInstantly() public {
        uint256 ts = vm.getBlockTimestamp();
        liusd.mint(address(account), 100e18);
        account.sync();
        usdc.mint(address(redeemController), 1000e6);

        // before maturity the position cannot be withdrawn and stays valued live
        account.sync();
        assertEq(account.unwindingTimestamps(0), ts);

        vm.warp(ts + UNWINDING_DURATION);
        assertEq(account.totalAssets(), 100e6);
        account.sync();

        // withdrawn iUSD is immediately redeemed against idle controller liquidity
        assertEq(iusd.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 100e6);
        vm.expectRevert();
        account.unwindingTimestamps(0);
        assertEq(account.totalAssets(), 100e6);
    }

    function testQueuePathValuesTicketsAtParAndClaims() public {
        uint256 ts = vm.getBlockTimestamp();
        liusd.mint(address(account), 100e18);
        account.sync();

        // no idle liquidity: the redeem enqueues a ticket for the full iUSD amount
        vm.warp(ts + UNWINDING_DURATION);
        account.sync();

        assertEq(iusd.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 0);
        (uint128 queueIndex, uint128 amount) = account.redemptionTickets(0);
        assertEq(queueIndex, 0);
        assertEq(amount, 100e18);
        assertEq(account.totalAssets(), 100e6);

        // funding pays the ticket into a pending claim; before the next sync the claim replaces
        // the queued value without double counting
        redeemController.fund(100e6);
        assertEq(redeemController.userPendingClaims(address(account)), 100e6);
        assertEq(account.totalAssets(), 100e6);

        // sync claims the funded ticket and prunes it
        account.sync();
        assertEq(usdc.balanceOf(address(account)), 100e6);
        vm.expectRevert();
        account.redemptionTickets(0);
        assertEq(account.totalAssets(), 100e6);
    }

    function testPartialLiquiditySplitsInstantAndQueuedRedemption() public {
        uint256 ts = vm.getBlockTimestamp();
        liusd.mint(address(account), 100e18);
        account.sync();
        usdc.mint(address(redeemController), 40e6);

        vm.warp(ts + UNWINDING_DURATION);
        account.sync();

        // 40 USDC paid instantly, the 60 iUSD remainder enqueued and valued at par
        assertEq(usdc.balanceOf(address(account)), 40e6);
        (, uint128 amount) = account.redemptionTickets(0);
        assertEq(amount, 60e18);
        assertEq(account.totalAssets(), 100e6);
    }

    function testPartialFundingTransientCountsParOnTopOfClaim() public {
        uint256 ts = vm.getBlockTimestamp();
        liusd.mint(address(account), 100e18);
        account.sync();

        // no idle liquidity: the full 100 iUSD is enqueued as a single ticket
        vm.warp(ts + UNWINDING_DURATION);
        account.sync();
        assertEq(account.totalAssets(), 100e6);

        // partial funding leaves the queue cursor on our ticket: the full par leg transiently
        // counts on top of the partial claim — the documented bounded overstatement
        redeemController.fund(40e6);
        assertEq(redeemController.userPendingClaims(address(account)), 40e6);
        assertEq(account.totalAssets(), 140e6);

        // funding the rest moves the cursor past the ticket: the par leg drops, the claim remains
        redeemController.fund(60e6);
        assertEq(redeemController.userPendingClaims(address(account)), 100e6);
        assertEq(account.totalAssets(), 100e6);

        // sync claims the funded ticket, prunes it and realizes the assets
        account.sync();
        assertEq(usdc.balanceOf(address(account)), 100e6);
        vm.expectRevert();
        account.redemptionTickets(0);
        assertEq(account.totalAssets(), 100e6);
    }

    function testTicketAtNonzeroQueueIndex() public {
        // a third party enqueues first, so the account's ticket lands at queue index 1
        address thirdParty = makeAddr("thirdParty");
        iusd.mint(thirdParty, 50e18);
        vm.startPrank(thirdParty);
        iusd.approve(address(redeemController), 50e18);
        redeemController.redeem(thirdParty, 50e18);
        vm.stopPrank();

        uint256 ts = vm.getBlockTimestamp();
        liusd.mint(address(account), 100e18);
        account.sync();
        vm.warp(ts + UNWINDING_DURATION);
        account.sync();

        (uint128 queueIndex, uint128 amount) = account.redemptionTickets(0);
        assertEq(queueIndex, 1);
        assertEq(amount, 100e18);
        assertEq(account.totalAssets(), 100e6);

        // funding the third-party entry moves the cursor onto our ticket: still valued at par
        redeemController.fund(50e6);
        assertEq(redeemController.userPendingClaims(address(account)), 0);
        assertEq(account.totalAssets(), 100e6);

        // funding our ticket switches valuation from par to the pending claim
        redeemController.fund(100e6);
        assertEq(redeemController.userPendingClaims(address(account)), 100e6);
        assertEq(account.totalAssets(), 100e6);

        // sync claims the funded ticket, prunes it and realizes the assets
        account.sync();
        assertEq(usdc.balanceOf(address(account)), 100e6);
        vm.expectRevert();
        account.redemptionTickets(0);
        assertEq(account.totalAssets(), 100e6);
    }

    function testDepegClaimBelowParDropsParLeg() public {
        uint256 ts = vm.getBlockTimestamp();
        liusd.mint(address(account), 100e18);
        account.sync();

        // no idle liquidity: the full 100 iUSD is enqueued and valued at par
        vm.warp(ts + UNWINDING_DURATION);
        account.sync();
        assertEq(account.totalAssets(), 100e6);

        // the ticket is funded below par: once the cursor passes it, the par leg drops and the
        // valuation uses the actual pending claim instead
        redeemController.setFundingRate(0.9e18);
        redeemController.fund(90e6);
        assertEq(redeemController.userPendingClaims(address(account)), 90e6);
        assertEq(account.totalAssets(), 90e6);

        // sync realizes the depegged claim
        account.sync();
        assertEq(usdc.balanceOf(address(account)), 90e6);
        assertEq(account.totalAssets(), 90e6);
    }

    function testSyncToleratesUnaccruedLosses() public {
        uint256 ts = vm.getBlockTimestamp();
        liusd.mint(address(account), 100e18);
        account.sync();

        // gateway reverts withdrawals/redemptions while protocol losses are unaccrued
        vm.warp(ts + UNWINDING_DURATION);
        gateway.setLossesUnaccrued(true);
        account.sync();

        assertEq(account.unwindingTimestamps(0), ts);
        assertEq(account.totalAssets(), 100e6);

        // once losses accrue, the next sync completes the withdrawal
        gateway.setLossesUnaccrued(false);
        usdc.mint(address(redeemController), 100e6);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 100e6);
        assertEq(account.totalAssets(), 100e6);
    }

    function testHeldIusdIsValuedAtParAcrossDecimals() public {
        // 100e18 iUSD-equivalents normalize to 100e6 vault assets
        iusd.mint(address(account), 100e18);
        assertEq(account.totalAssets(), 100e6);
    }

    function testLiUSDAccountsHardcodeMainnetWiring() public {
        address liUSD4w = 0x66bCF6151D5558AfB47c38B20663589843156078;
        address liUSD13w = 0xbd3f9814eB946E617f1d774A6762cDbec0bf087A;
        vm.mockCall(liUSD4w, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(liUSD13w, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        liUSD4w_Account account4w = new liUSD4w_Account(address(factory), cowSettlement);
        liUSD13w_Account account13w = new liUSD13w_Account(address(factory), cowSettlement);

        assertEq(account4w.TOKEN_TO_REDEEM(), liUSD4w);
        assertEq(account4w.COOLDOWN(), 3 days);
        assertEq(account4w.UNWINDING_EPOCHS(), 4);
        assertEq(ChainlinkOracle(account4w.ORACLE()).AGGREGATOR_0(), 0xF8472D8D3Ef3f8aEb83A2B09aC69f40dF1ace66c);

        assertEq(account13w.TOKEN_TO_REDEEM(), liUSD13w);
        assertEq(account13w.COOLDOWN(), 7 days);
        assertEq(account13w.UNWINDING_EPOCHS(), 13);
        assertEq(ChainlinkOracle(account13w.ORACLE()).AGGREGATOR_0(), 0x8D5FFAa15730D87C90C34A4c2e80684043704417);

        address[2] memory accounts = [address(account4w), address(account13w)];
        for (uint256 i; i < accounts.length; ++i) {
            InfiniFiAccount tokenAccount = InfiniFiAccount(accounts[i]);
            assertEq(tokenAccount.GATEWAY(), 0x3f04b65Ddbd87f9CE0A2e7Eb24d80e7fb87625b5);
            assertEq(tokenAccount.UNWINDING_MODULE(), 0x7092A43aE5407666C78dBEA657a1891f42b3dFcc);
            assertEq(tokenAccount.REDEEM_CONTROLLER(), 0xCb1747E89a43DEdcF4A2b831a0D94859EFeC7601);
            assertEq(tokenAccount.IUSD(), 0x48f9e38f3070AD8945DFEae3FA70987722E3D89c);
            assertEq(ChainlinkOracle(tokenAccount.ORACLE()).AGGREGATOR_1(), address(0));
            assertEq(ChainlinkOracle(tokenAccount.ORACLE()).STALENESS_DURATION_0(), 30 days);
        }
    }
}

contract MockVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract MockERC20 is ERC20 {
    uint8 internal immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockOracle {
    uint256 internal _price;

    constructor(uint256 price_) {
        _price = price_;
    }

    function setPrice(uint256 price_) external {
        _price = price_;
    }

    function getPrice() external view returns (uint256) {
        return _price;
    }
}

contract MockInfiniFiUnwindingModule {
    struct Position {
        uint256 balance;
        uint256 maturity;
    }

    error UserNotUnwinding();
    error UserUnwindingInprogress();

    MockERC20 internal immutable _iusd;

    mapping(address user => mapping(uint256 timestamp => Position position)) internal _positions;

    constructor(MockERC20 iusd_) {
        _iusd = iusd_;
    }

    function open(address user, uint256 amount) external {
        if (_positions[user][block.timestamp].maturity != 0) {
            revert UserUnwindingInprogress();
        }
        _positions[user][block.timestamp] = Position({
            balance: amount, maturity: block.timestamp + MockInfiniFiGateway(msg.sender).unwindingDuration()
        });
    }

    function setBalance(address user, uint256 timestamp, uint256 balance) external {
        _positions[user][timestamp].balance = balance;
    }

    function balanceOf(address user, uint256 timestamp) external view returns (uint256) {
        return _positions[user][timestamp].balance;
    }

    function withdraw(address user, uint256 timestamp) external {
        Position memory position = _positions[user][timestamp];
        if (position.maturity == 0) {
            revert UserNotUnwinding();
        }
        if (block.timestamp < position.maturity) {
            revert UserUnwindingInprogress();
        }
        delete _positions[user][timestamp];
        _iusd.mint(user, position.balance);
    }
}

contract MockInfiniFiRedeemController {
    error NoPendingClaims(address recipient);

    MockERC20 internal immutable _usdc;
    MockERC20 internal immutable _iusd;

    uint128 internal _begin;
    uint128 internal _end;
    uint256 public totalEnqueuedRedemptions;
    uint256 public totalPendingClaims;
    uint256 public fundingRate = 1e18;

    mapping(uint128 index => uint128 amount) public ticketAmounts;
    mapping(uint128 index => address recipient) public ticketRecipients;
    mapping(address recipient => uint256 assets) public userPendingClaims;

    constructor(MockERC20 usdc_, MockERC20 iusd_) {
        _usdc = usdc_;
        _iusd = iusd_;
    }

    function assetToken() external view returns (address) {
        return address(_usdc);
    }

    function queue() external view returns (uint128 begin, uint128 end) {
        return (_begin, _end);
    }

    function liquidity() public view returns (uint256) {
        return _usdc.balanceOf(address(this)) - totalPendingClaims;
    }

    function redeem(address to, uint256 amount) external returns (uint256) {
        IERC20(address(_iusd)).transferFrom(msg.sender, address(this), amount);

        if (_end > _begin) {
            _enqueue(to, amount);
            return 0;
        }

        uint256 assetsOut = _toAssets(amount);
        uint256 available = liquidity();
        if (assetsOut <= available) {
            _usdc.transfer(to, assetsOut);
            return assetsOut;
        }

        _usdc.transfer(to, available);
        _enqueue(to, amount - _toReceipt(available));
        return available;
    }

    function setFundingRate(uint256 fundingRate_) external {
        fundingRate = fundingRate_;
    }

    function fund(uint256 assetAmount) external {
        _usdc.mint(address(this), assetAmount);

        uint256 remaining = assetAmount;
        while (remaining > 0 && _begin < _end) {
            uint256 required = _toAssets(ticketAmounts[_begin]) * fundingRate / 1e18;
            if (required > remaining) {
                uint128 receiptFunded = uint128(_toReceipt(remaining * 1e18 / fundingRate));
                ticketAmounts[_begin] -= receiptFunded;
                totalEnqueuedRedemptions -= receiptFunded;
                userPendingClaims[ticketRecipients[_begin]] += remaining;
                totalPendingClaims += remaining;
                remaining = 0;
            } else {
                totalEnqueuedRedemptions -= ticketAmounts[_begin];
                userPendingClaims[ticketRecipients[_begin]] += required;
                totalPendingClaims += required;
                remaining -= required;
                delete ticketAmounts[_begin];
                delete ticketRecipients[_begin];
                ++_begin;
            }
        }
    }

    function claimRedemption(address recipient) external {
        uint256 amount = userPendingClaims[recipient];
        if (amount == 0) {
            revert NoPendingClaims(recipient);
        }
        userPendingClaims[recipient] = 0;
        totalPendingClaims -= amount;
        _usdc.transfer(recipient, amount);
    }

    function _enqueue(address recipient, uint256 amount) internal {
        ticketAmounts[_end] = uint128(amount);
        ticketRecipients[_end] = recipient;
        ++_end;
        totalEnqueuedRedemptions += amount;
    }

    function _toAssets(uint256 receiptAmount) internal view returns (uint256) {
        return receiptAmount * 10 ** _usdc.decimals() / 10 ** _iusd.decimals();
    }

    function _toReceipt(uint256 assetAmount) internal view returns (uint256) {
        return assetAmount * 10 ** _iusd.decimals() / 10 ** _usdc.decimals();
    }
}

contract MockInfiniFiGateway {
    error MinAssetsOutError(uint256 min, uint256 actual);
    error PendingLossesUnapplied();

    MockERC20 internal immutable _liusd;
    MockERC20 internal immutable _iusd;
    MockInfiniFiUnwindingModule internal immutable _unwindingModule;
    MockInfiniFiRedeemController internal immutable _redeemController;

    uint256 public unwindingDuration;
    uint256 public exchangeRate = 1e18;
    bool public lossesUnaccrued;

    constructor(
        MockERC20 liusd_,
        MockERC20 iusd_,
        MockInfiniFiUnwindingModule unwindingModule_,
        MockInfiniFiRedeemController redeemController_,
        uint256 unwindingDuration_
    ) {
        _liusd = liusd_;
        _iusd = iusd_;
        _unwindingModule = unwindingModule_;
        _redeemController = redeemController_;
        unwindingDuration = unwindingDuration_;
    }

    function setExchangeRate(uint256 exchangeRate_) external {
        exchangeRate = exchangeRate_;
    }

    function setLossesUnaccrued(bool lossesUnaccrued_) external {
        lossesUnaccrued = lossesUnaccrued_;
    }

    function startUnwinding(uint256 shares, uint32) external {
        IERC20(address(_liusd)).transferFrom(msg.sender, address(this), shares);
        _unwindingModule.open(msg.sender, shares * exchangeRate / 1e18);
    }

    function withdraw(uint256 unwindingTimestamp) external {
        if (lossesUnaccrued) {
            revert PendingLossesUnapplied();
        }
        _unwindingModule.withdraw(msg.sender, unwindingTimestamp);
    }

    function redeem(address to, uint256 amount, uint256 minAssetsOut) external returns (uint256) {
        if (lossesUnaccrued) {
            revert PendingLossesUnapplied();
        }
        IERC20(address(_iusd)).transferFrom(msg.sender, address(this), amount);
        _iusd.approve(address(_redeemController), amount);
        uint256 assetsOut = _redeemController.redeem(to, amount);
        if (assetsOut < minAssetsOut) {
            revert MinAssetsOutError(minAssetsOut, assetsOut);
        }
        return assetsOut;
    }

    function claimRedemption() external {
        _redeemController.claimRedemption(msg.sender);
    }
}

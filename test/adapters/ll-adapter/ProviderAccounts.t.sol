// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccountsBase, MockERC20, MockOracle} from "./AccountsBase.t.sol";

import {NoonAccount} from "../../../src/contracts/adapters/ll-adapter/NoonAccount.sol";
import {ParetoAccount} from "../../../src/contracts/adapters/ll-adapter/ParetoAccount.sol";
import {SecuritizeAccount} from "../../../src/contracts/adapters/ll-adapter/SecuritizeAccount.sol";
import {SuperstateAccount} from "../../../src/contracts/adapters/ll-adapter/SuperstateAccount.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProviderAccountsTest is AccountsBase {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint48 internal constant PENDING_ASSETS_DURATION = 3 days;

    function testNoonRequestsAndClaimsThroughWithdrawalHandler() public {
        MockERC20 usn = new MockERC20("USN", "USN", 18);
        MockNoonWithdrawalHandler withdrawalHandler = new MockNoonWithdrawalHandler(usn, TOKEN_COOLDOWN);
        MockNoonSUSN susn = new MockNoonSUSN(usn, withdrawalHandler, 12e17);
        NoonAccount account = _deployNoon(susn, usn, withdrawalHandler);

        susn.mint(address(account), 10 ether);

        account.sync();

        assertEq(susn.balanceOf(address(account)), 0);
        assertEq(account.requestIds(0), 0);
        assertEq(account.totalAssets(), 12 ether);

        vm.warp(vm.getBlockTimestamp() + TOKEN_COOLDOWN);
        account.sync();

        assertEq(usn.balanceOf(address(account)), 12 ether);
        assertEq(account.totalAssets(), 12 ether);
        vm.expectRevert();
        account.requestIds(0);
    }

    function testParetoRequestsAndClaimsWithdrawalReceipts() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockParetoTranche tranche = new MockParetoTranche();
        MockParetoCreditVault creditVault = new MockParetoCreditVault();
        MockParetoCDO idleCdo = new MockParetoCDO(usdc, tranche, creditVault, 11e5);
        ParetoAccount account = _deployPareto(tranche, usdc, idleCdo);

        tranche.mint(address(account), 2 ether);

        account.sync();

        assertEq(tranche.balanceOf(address(account)), 0);
        assertEq(creditVault.balanceOf(address(account)), 22e5);
        assertEq(account.totalAssets(), 22e5);

        idleCdo.setEpochNumber(1);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 22e5);
        assertEq(creditVault.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 22e5);
    }

    function testSuperstateBurnsInSubAccountAndSweepsSettlement() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        SuperstateAccount account = _deploySuperstate(uscc, usdc);

        uscc.mint(address(account), 1e6);

        account.sync();

        address subAccount = account.subAccounts(0);
        assertEq(uscc.balanceOf(address(account)), 0);
        assertEq(uscc.redeemed(subAccount), 1e6);
        assertEq(account.totalAssets(), 11e6);

        usdc.mint(subAccount, 11e6);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 11e6);
        assertEq(account.totalAssets(), 11e6);
        vm.expectRevert();
        account.subAccounts(0);
    }

    function testSecuritizeBurnsInSubAccountAndExpiresPendingValue() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSecuritizeToken acred = new MockSecuritizeToken();
        SecuritizeAccount account = _deploySecuritize(acred, usdc);

        acred.mint(address(account), 1e6);

        account.sync();

        address subAccount = account.subAccounts(0);
        assertEq(acred.balanceOf(address(account)), 0);
        assertEq(acred.burned(subAccount), 1e6);
        assertEq(account.totalAssets(), 11e6);

        vm.warp(vm.getBlockTimestamp() + PENDING_ASSETS_DURATION);

        assertEq(account.totalAssets(), 0);
    }

    function _deployNoon(MockNoonSUSN susn, MockERC20 asset, MockNoonWithdrawalHandler withdrawalHandler)
        internal
        returns (NoonAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        NoonAccount implementation = new NoonAccount(
            address(new MockOracle(1e18)),
            address(factory),
            TOKEN_COOLDOWN,
            address(susn),
            address(withdrawalHandler),
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = NoonAccount(factory.create(1, address(this), _initData(address(asset), address(susn))));
    }

    function _deployPareto(MockParetoTranche tranche, MockERC20 asset, MockParetoCDO idleCdo)
        internal
        returns (ParetoAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        ParetoAccount implementation = new ParetoAccount(
            address(new MockOracle(1e18)),
            address(factory),
            TOKEN_COOLDOWN,
            address(tranche),
            address(idleCdo),
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = ParetoAccount(factory.create(1, address(this), _initData(address(asset), address(tranche))));
    }

    function _deploySuperstate(MockSuperstateToken uscc, MockERC20 asset) internal returns (SuperstateAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        SuperstateAccount implementation = new SuperstateAccount(
            address(new MockOracle(11e18)),
            address(factory),
            TOKEN_COOLDOWN,
            address(uscc),
            PENDING_ASSETS_DURATION,
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = SuperstateAccount(factory.create(1, address(this), _initData(address(asset), address(uscc))));
    }

    function _deploySecuritize(MockSecuritizeToken acred, MockERC20 asset)
        internal
        returns (SecuritizeAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        SecuritizeAccount implementation = new SecuritizeAccount(
            address(new MockOracle(11e18)),
            address(factory),
            TOKEN_COOLDOWN,
            address(acred),
            PENDING_ASSETS_DURATION,
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = SecuritizeAccount(factory.create(1, address(this), _initData(address(asset), address(acred))));
    }
}

contract MockNoonSUSN is MockERC20 {
    MockERC20 internal immutable _asset;
    MockNoonWithdrawalHandler internal immutable _withdrawalHandler;
    uint256 internal immutable _assetsPerShare;

    constructor(MockERC20 asset_, MockNoonWithdrawalHandler withdrawalHandler_, uint256 assetsPerShare_)
        MockERC20("Staked USN", "sUSN", 18)
    {
        _asset = asset_;
        _assetsPerShare = assetsPerShare_;
        _withdrawalHandler = withdrawalHandler_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * _assetsPerShare / 1e18;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(receiver == address(_withdrawalHandler));
        require(owner == msg.sender);

        assets = convertToAssets(shares);
        _burn(owner, shares);
        _asset.mint(receiver, assets);
        _withdrawalHandler.createWithdrawalRequest(owner, assets);
    }
}

contract MockNoonWithdrawalHandler {
    struct WithdrawalRequest {
        uint256 amount;
        uint256 timestamp;
        bool claimed;
    }

    MockERC20 public immutable usn;
    uint48 public immutable withdrawPeriod;

    mapping(address user => uint256 nextId) public nextRequestId;
    mapping(address user => mapping(uint256 requestId => WithdrawalRequest request)) public withdrawalRequests;

    constructor(MockERC20 usn_, uint48 withdrawPeriod_) {
        usn = usn_;
        withdrawPeriod = withdrawPeriod_;
    }

    function createWithdrawalRequest(address user, uint256 amount) external returns (uint256 requestId) {
        requestId = nextRequestId[user];
        withdrawalRequests[user][requestId] =
            WithdrawalRequest({amount: amount, timestamp: block.timestamp, claimed: false});
        ++nextRequestId[user];
    }

    function getUserNextRequestId(address user) external view returns (uint256) {
        return nextRequestId[user];
    }

    function getWithdrawalRequest(address user, uint256 requestId) external view returns (WithdrawalRequest memory) {
        return withdrawalRequests[user][requestId];
    }

    function claimWithdrawal(uint256 requestId) external {
        WithdrawalRequest storage request = withdrawalRequests[msg.sender][requestId];
        require(block.timestamp >= request.timestamp + withdrawPeriod);
        request.claimed = true;
        IERC20(address(usn)).transfer(msg.sender, request.amount);
    }
}

contract MockParetoTranche is MockERC20 {
    constructor() MockERC20("Pareto AA Tranche", "AA_FalconXUSDC", 18) {}
}

contract MockParetoCreditVault is MockERC20 {
    constructor() MockERC20("Pareto Credit Vault", "cvUSDC", 6) {}

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

contract MockParetoCDO {
    MockERC20 public immutable token;
    MockParetoTranche public immutable tranche;
    MockParetoCreditVault public immutable strategy;
    uint256 public epochNumber;
    uint256 public virtualPrice;

    mapping(address account => uint256 epoch) public lastWithdrawRequest;

    constructor(MockERC20 token_, MockParetoTranche tranche_, MockParetoCreditVault strategy_, uint256 virtualPrice_) {
        token = token_;
        tranche = tranche_;
        strategy = strategy_;
        virtualPrice = virtualPrice_;
    }

    function setEpochNumber(uint256 epochNumber_) external {
        epochNumber = epochNumber_;
    }

    function requestWithdraw(uint256 amount, address curTranche) external returns (uint256 assets) {
        require(curTranche == address(tranche));

        assets = amount * virtualPrice / 1e18;
        IERC20(curTranche).transferFrom(msg.sender, address(this), amount);
        strategy.mint(msg.sender, assets);
        lastWithdrawRequest[msg.sender] = epochNumber;
    }

    function claimWithdrawRequest() external {
        require(epochNumber > lastWithdrawRequest[msg.sender]);

        uint256 assets = strategy.balanceOf(msg.sender);
        strategy.burn(msg.sender, assets);
        token.mint(msg.sender, assets);
    }
}

contract MockSuperstateToken is MockERC20 {
    mapping(address account => uint256 amount) public redeemed;

    constructor() MockERC20("Superstate Crypto Carry Fund", "USCC", 6) {}

    function offchainRedeem(uint256 amount) external {
        _burn(msg.sender, amount);
        redeemed[msg.sender] += amount;
    }
}

contract MockSecuritizeToken is MockERC20 {
    mapping(address account => uint256 amount) public burned;

    constructor() MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6) {}

    function burn(address account, uint256 amount, string calldata) external {
        require(account == msg.sender);
        _burn(account, amount);
        burned[account] += amount;
    }
}

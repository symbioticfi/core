// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccountsBase, MockERC20, MockOracle, MockPriceDataOracle} from "./AccountsBase.t.sol";

import {NoonAccount} from "../../../src/contracts/adapters/ll-adapter/NoonAccount.sol";
import {ParetoAccount} from "../../../src/contracts/adapters/ll-adapter/ParetoAccount.sol";
import {SecuritizeAccount} from "../../../src/contracts/adapters/ll-adapter/SecuritizeAccount.sol";
import {SuperstateAccount} from "../../../src/contracts/adapters/ll-adapter/SuperstateAccount.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {ISettlementAccount} from "../../../src/interfaces/adapters/ll-adapter/ISettlementAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProviderAccountsTest is AccountsBase {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint48 internal constant SETTLEMENT_DURATION = 3 days;

    address internal redemptionWallet = makeAddr("redemptionWallet");

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

    function testSuperstateBurnsRequestsFreezeAndSweepsSettlement() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SuperstateAccount account = _deploySuperstate(uscc, usdc, oracle);

        uscc.mint(address(account), 1e6);

        account.sync();

        address subAccount = account.subAccounts(0);
        assertEq(uscc.balanceOf(address(account)), 0);
        assertEq(uscc.redeemed(subAccount), 1e6);
        assertEq(account.totalAssets(), 11e6);

        // pending value tracks the live oracle until the cohort rate freezes
        oracle.setPriceData(12e18, uint48(vm.getBlockTimestamp()));
        assertEq(account.totalAssets(), 12e6);

        // oracle print at/after the request time freezes the rate on the next sync
        account.sync();
        oracle.setPriceData(20e18, uint48(vm.getBlockTimestamp()));
        assertEq(account.totalAssets(), 12e6);

        // settlement covering the frozen cohort value is swept and releases the subaccount
        usdc.mint(subAccount, 12e6);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 12e6);
        assertEq(account.totalAssets(), 12e6);
        vm.expectRevert();
        account.subAccounts(0);
    }

    function testSuperstateWriteOffKeepsSubAccountTrackedForLateSettlement() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SuperstateAccount account = _deploySuperstate(uscc, usdc, oracle);

        uscc.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);
        account.sync(); // freezes the cohort rate at 11e18

        // no settlement: the receivable is written off but the subaccount stays tracked
        vm.warp(vm.getBlockTimestamp() + SETTLEMENT_DURATION);
        assertEq(account.totalAssets(), 0);
        assertEq(account.subAccounts(0), subAccount);

        // a late settlement is still sweepable and restores the value
        usdc.mint(subAccount, 11e6);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 11e6);
        assertEq(account.totalAssets(), 11e6);
        vm.expectRevert();
        account.subAccounts(0);
    }

    function testSuperstateDustDonationDoesNotReleaseSubAccount() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SuperstateAccount account = _deploySuperstate(uscc, usdc, oracle);

        uscc.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);

        // 1 wei donation pre-settlement only reduces the remaining receivable one-for-one
        usdc.mint(subAccount, 1);
        account.sync();

        assertEq(account.subAccounts(0), subAccount);
        assertEq(account.receivedValues(uint160(subAccount)), 1);
        assertEq(account.totalAssets(), 11e6);
    }

    function testSuperstateNeverFrozenWriteOffDustDoesNotReleaseSubAccount() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SuperstateAccount account = _deploySuperstate(uscc, usdc, oracle);

        // register after the oracle's last print so the cohort rate can never freeze
        vm.warp(vm.getBlockTimestamp() + 1);
        uscc.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);

        // oracle never prints at/after the pricing date: written off without ever freezing
        vm.warp(vm.getBlockTimestamp() + SETTLEMENT_DURATION);
        assertEq(account.totalAssets(), 0);

        // a 1 wei donation must not release the never-frozen written-off subaccount
        usdc.mint(subAccount, 1);
        account.sync();

        assertEq(account.subAccounts(0), subAccount);
        assertEq(account.receivedValues(uint160(subAccount)), 1);

        // a late full settlement is still swept to the parent: funds recovered
        usdc.mint(subAccount, 11e6);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 11e6 + 1);
        assertEq(usdc.balanceOf(subAccount), 0);
        assertEq(account.totalAssets(), 11e6 + 1);
    }

    function testSuperstateTranchedSettlementReleasesOnFullCoverage() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SuperstateAccount account = _deploySuperstate(uscc, usdc, oracle);

        uscc.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);
        account.sync(); // freezes the cohort rate at 11e18 (cohort value 11e6)

        // first tranche (60%): swept but the subaccount is retained
        usdc.mint(subAccount, 6_600_000);
        account.sync();

        assertEq(account.subAccounts(0), subAccount);
        assertEq(usdc.balanceOf(address(account)), 6_600_000);
        assertEq(account.totalAssets(), 11e6);

        // second tranche (40%): coverage met, subaccount released
        usdc.mint(subAccount, 4_400_000);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 11e6);
        assertEq(account.totalAssets(), 11e6);
        vm.expectRevert();
        account.subAccounts(0);
    }

    function testSuperstateSweepAndReleaseEmitEvents() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SuperstateAccount account = _deploySuperstate(uscc, usdc, oracle);

        uscc.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);
        account.sync(); // freezes the cohort rate at 11e18 (cohort value 11e6)

        // partial tranche: the sweep is credited, no release
        usdc.mint(subAccount, 6_600_000);
        vm.expectEmit(true, true, true, true, address(account));
        emit ISettlementAccount.SweepSubAccount(subAccount, 6_600_000, 0);
        account.sync();

        // closing tranche: the sweep is credited and the value-covered subaccount is released
        usdc.mint(subAccount, 4_400_000);
        vm.expectEmit(true, true, true, true, address(account));
        emit ISettlementAccount.SweepSubAccount(subAccount, 4_400_000, 0);
        vm.expectEmit(true, true, true, true, address(account));
        emit ISettlementAccount.ReleaseSubAccount(subAccount);
        account.sync();
    }

    function testSecuritizeTransfersNoticeToRedemptionWallet() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle);

        acred.mint(address(account), 1e6);

        account.sync();

        address subAccount = account.subAccounts(0);
        assertEq(acred.balanceOf(address(account)), 0);
        assertEq(acred.balanceOf(subAccount), 0);
        assertEq(acred.balanceOf(redemptionWallet), 1e6); // plain transfer notice, no burn
        assertEq(account.totalAssets(), 11e6); // pending valued live
    }

    function testSecuritizeSweepsPartialFillRemint() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle);
        address keeper = makeAddr("keeper");

        acred.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);
        account.sync(); // freezes the cohort rate at 11e18 (cohort value 11e6)

        // quarterly settlement: 35% repurchased in USDC, 65% re-minted as ACRED
        usdc.mint(subAccount, 3_850_000);
        acred.mint(subAccount, 650_000);
        assertEq(account.totalAssets(), 11e6);

        vm.prank(keeper);
        account.sync();

        // both legs swept to the parent; coverage met at the live rate -> subaccount released
        assertEq(usdc.balanceOf(address(account)), 3_850_000);
        assertEq(acred.balanceOf(address(account)), 650_000);
        assertEq(account.totalAssets(), 11e6);
        vm.expectRevert();
        account.subAccounts(0);

        // post-cooldown sync re-tenders the re-minted tokens into a new subaccount
        vm.warp(vm.getBlockTimestamp() + TOKEN_COOLDOWN);
        vm.prank(keeper);
        account.sync();

        address newSubAccount = account.subAccounts(0);
        assertNotEq(newSubAccount, subAccount);
        assertEq(acred.balanceOf(address(account)), 0);
        assertEq(acred.balanceOf(redemptionWallet), 1_650_000);
        assertEq(account.totalAssets(), 11e6);
    }

    function testSecuritizeRemintBelowFrozenRateRetainsSubAccount() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle);
        address keeper = makeAddr("keeper");

        acred.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);
        account.sync(); // freezes the cohort rate at 11e18 (cohort value 11e6)

        // settlement: 35% repurchased in USDC, 65% re-minted, with the live rate now 10% below frozen
        oracle.setPriceData(9.9e18, uint48(vm.getBlockTimestamp()));
        usdc.mint(subAccount, 3_850_000);
        acred.mint(subAccount, 650_000);

        vm.prank(keeper);
        account.sync();

        // credited at the live rate: 3_850_000 + 650_000 * 9.9 = 10_285_000 < 11e6 -> retained
        assertEq(account.subAccounts(0), subAccount);
        assertEq(account.receivedValues(uint160(subAccount)), 10_285_000);
        assertEq(usdc.balanceOf(address(account)), 3_850_000);
        assertEq(acred.balanceOf(address(account)), 650_000);
        // holdings (3_850_000 USDC + 650_000 ACRED live = 6_435_000) + remaining receivable 715_000
        assertEq(account.totalAssets(), 11e6);

        // anyone topping up the shortfall to the subaccount triggers release on the next sync
        usdc.mint(subAccount, 715_000);
        vm.prank(keeper);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 4_565_000);
        assertEq(account.totalAssets(), 11e6);
        vm.expectRevert();
        account.subAccounts(0);
    }

    function testSecuritizeRemintAfterWriteOffIsSweptAndRetained() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        // settlement duration below the cooldown so the post-write-off sweep does not re-tender
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle, 0, 0, 0, 12 hours);
        address keeper = makeAddr("keeper");

        // register after the oracle's last print so the cohort rate can never freeze
        vm.warp(vm.getBlockTimestamp() + 1);
        acred.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);

        // oracle never prints at/after the pricing date: written off without ever freezing
        vm.warp(vm.getBlockTimestamp() + 12 hours);
        assertEq(account.totalAssets(), 0);

        // the full notice is re-minted to the subaccount after the write-off
        acred.mint(subAccount, 1e6);
        vm.prank(keeper);
        account.sync();

        // tokens swept to the parent as live inventory; a never-frozen entry is never released
        assertEq(acred.balanceOf(address(account)), 1e6);
        assertEq(acred.balanceOf(subAccount), 0);
        assertEq(account.subAccounts(0), subAccount);
        assertEq(account.receivedValues(uint160(subAccount)), 11e6);
        assertEq(account.totalAssets(), 11e6); // live value of the swept tokens only
    }

    function testSecuritizeFreezesCohortRateAfterPricingDate() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        uint48 cutoff = uint48(vm.getBlockTimestamp()) + 10 days;
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle, cutoff, 91 days, 5 days, 30 days);

        acred.mint(address(account), 1e6);

        account.sync();

        address subAccount = account.subAccounts(0);
        (,, uint48 cohortCutoff) = account.pendingCohorts(uint160(subAccount));
        assertEq(cohortCutoff, cutoff);
        assertEq(account.totalAssets(), 1e6);

        // first oracle print at/after the pricing date freezes the cohort rate
        uint48 pricingTime = cutoff + 5 days;
        vm.warp(pricingTime + 1);
        oracle.setPriceData(1.2e18, pricingTime + 1);
        account.sync();

        oracle.setPriceData(2e18, uint48(vm.getBlockTimestamp()));
        assertEq(account.totalAssets(), 1_200_000);

        // unsettled past the settlement duration: written off
        vm.warp(pricingTime + 30 days);
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

    function _deploySuperstate(MockSuperstateToken uscc, MockERC20 asset, MockPriceDataOracle oracle)
        internal
        returns (SuperstateAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        SuperstateAccount implementation = new SuperstateAccount(
            address(oracle), address(factory), TOKEN_COOLDOWN, address(uscc), SETTLEMENT_DURATION, cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = SuperstateAccount(factory.create(1, address(this), _initData(address(asset), address(uscc))));
    }

    function _deploySecuritize(MockERC20 acred, MockERC20 asset, MockPriceDataOracle oracle)
        internal
        returns (SecuritizeAccount account)
    {
        account = _deploySecuritize(acred, asset, oracle, 0, 0, 0, SETTLEMENT_DURATION);
    }

    function _deploySecuritize(
        MockERC20 acred,
        MockERC20 asset,
        MockPriceDataOracle oracle,
        uint48 initialCutoff,
        uint48 initialCutoffPeriod,
        uint48 valuationDelay,
        uint48 settlementDuration
    ) internal returns (SecuritizeAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        SecuritizeAccount implementation = new SecuritizeAccount(
            address(oracle),
            address(factory),
            TOKEN_COOLDOWN,
            address(acred),
            redemptionWallet,
            initialCutoff,
            initialCutoffPeriod,
            valuationDelay,
            settlementDuration,
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccountsBase, MockERC20, MockOracle, MockPriceDataOracle} from "./AccountsBase.t.sol";

import {AssetoAccount} from "../../../src/contracts/adapters/ll-adapter/AssetoAccount.sol";
import {AssetoOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/AssetoOracle.sol";
import {NoonAccount} from "../../../src/contracts/adapters/ll-adapter/NoonAccount.sol";
import {OpenEdenAccount} from "../../../src/contracts/adapters/ll-adapter/OpenEdenAccount.sol";
import {ParetoAccount} from "../../../src/contracts/adapters/ll-adapter/ParetoAccount.sol";
import {
    AcredSecuritizeAccount,
    SecuritizeAccount
} from "../../../src/contracts/adapters/ll-adapter/SecuritizeAccount.sol";
import {SuperstateAccount} from "../../../src/contracts/adapters/ll-adapter/SuperstateAccount.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAssetoAccount} from "../../../src/interfaces/adapters/ll-adapter/asseto/IAssetoAccount.sol";
import {IOpenEdenAccount} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenAccount.sol";
import {ISettlementAccount} from "../../../src/interfaces/adapters/ll-adapter/ISettlementAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProviderAccountsTest is AccountsBase {
    bytes32 internal constant ASSETO_DESTINATION = bytes32("AoABT_red_test");
    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint48 internal constant SETTLEMENT_DURATION = 3 days;

    address internal redemptionWallet = makeAddr("redemptionWallet");

    function testAssetoOracleReadsLatestPriceData() public {
        MockAssetoPricer pricer = new MockAssetoPricer(975e18, uint48(vm.getBlockTimestamp()));
        AssetoOracle oracle = new AssetoOracle(address(pricer));

        assertEq(oracle.getPrice(), 975e18);

        pricer.setPrice(2, 976e18, uint48(vm.getBlockTimestamp() + 1));

        (uint256 price, uint48 updatedAt) = oracle.getPriceData();
        assertEq(price, 976e18);
        assertEq(updatedAt, uint48(vm.getBlockTimestamp() + 1));
    }

    function testAssetoBurnsThroughManagerAndTracksCutoff() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        MockAssetoToken aoabt = new MockAssetoToken("Asseto Open-Ended ABT Fund", "AoABT", 18);
        MockAssetoPricer pricer = new MockAssetoPricer(11e18, uint48(vm.getBlockTimestamp()));
        MockAssetoManager manager = new MockAssetoManager(address(aoabt), address(usdt), 100e18, 5000e18);
        AssetoAccount account = _deployAsseto(aoabt, usdc, address(new AssetoOracle(address(pricer))), manager);

        aoabt.mint(address(account), 150e18);

        account.sync();

        (uint256 amount, uint48 bucketIndex) = account.pendingCutoffs(0);
        (uint256 totalTokenToRedeem, uint256 pendingTokenToRedeem,) = account.buckets(bucketIndex);

        assertEq(aoabt.balanceOf(address(account)), 0);
        assertEq(manager.redemptionRequestCounter(), 1);
        assertEq(manager.lastAmount(), 150e18);
        assertEq(manager.lastOffChainDestination(), ASSETO_DESTINATION);
        assertEq(amount, 150e18);
        assertEq(totalTokenToRedeem, 150e18);
        assertEq(pendingTokenToRedeem, 150e18);
        assertEq(account.totalAssets(), 1650e6);
    }

    function testAssetoClearsPendingWhenSettlementCollateralCoversValue() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        MockAssetoToken aoabt = new MockAssetoToken("Asseto Open-Ended ABT Fund", "AoABT", 18);
        MockAssetoPricer pricer = new MockAssetoPricer(11e18, uint48(vm.getBlockTimestamp()));
        MockAssetoManager manager = new MockAssetoManager(address(aoabt), address(usdt), 100e18, 5000e18);
        AssetoAccount account = _deployAsseto(aoabt, usdc, address(new AssetoOracle(address(pricer))), manager);

        aoabt.mint(address(account), 150e18);
        account.sync();

        usdt.mint(address(account), 1650e6);

        assertEq(account.totalAssets(), 1650e6);

        account.sync();

        (uint256 amount,) = account.pendingCutoffs(0);
        assertEq(amount, 0);
        assertEq(usdt.balanceOf(address(account)), 1650e6);
        assertEq(account.totalAssets(), 1650e6);
    }

    function testAssetoSkipsBelowMinimumAndCapsAtMaximum() public {
        vm.warp(1 days);

        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        MockAssetoToken aoabt = new MockAssetoToken("Asseto Open-Ended ABT Fund", "AoABT", 18);
        MockAssetoPricer pricer = new MockAssetoPricer(1e18, uint48(vm.getBlockTimestamp()));
        MockAssetoManager manager = new MockAssetoManager(address(aoabt), address(usdt), 100e18, 5000e18);
        AssetoAccount account = _deployAsseto(aoabt, usdc, address(new AssetoOracle(address(pricer))), manager);

        aoabt.mint(address(account), 99e18);
        account.sync();

        assertEq(manager.redemptionRequestCounter(), 0);
        assertEq(account.lastRequestTimestamp(), 0);
        assertEq(aoabt.balanceOf(address(account)), 99e18);

        aoabt.mint(address(account), 5100e18);
        account.sync();

        (uint256 amount,) = account.pendingCutoffs(0);
        assertEq(amount, 5000e18);
        assertEq(manager.redemptionRequestCounter(), 1);
        assertEq(account.lastRequestTimestamp(), uint48(vm.getBlockTimestamp()));
        assertEq(aoabt.balanceOf(address(account)), 199e18);
    }

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

    function testOpenEdenRequestsAndValuesQueuedRedeems() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle oracle = new MockOracle(12e17);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, oracle);
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, oracle, express);

        hybond.mint(address(account), 2 ether);

        assertEq(account.totalAssets(), 2_397_600);

        account.sync();

        assertEq(hybond.balanceOf(address(account)), 0);
        assertEq(hybond.balanceOf(address(express)), 2 ether);
        assertEq(express.pendingRedeemInfo(address(account)), 2 ether);
        assertEq(account.totalAssets(), 2_397_600);

        express.processPending(address(account), 1 ether);
        assertEq(account.totalAssets(), 2_397_600);

        express.processRedeem(address(account), 1 ether);
        assertEq(usdc.balanceOf(address(account)), 1_198_800);
        assertEq(account.totalAssets(), 2_397_600);
    }

    function testOpenEdenRejectsUnexpectedRedeemAsset() public {
        MockERC20 dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle oracle = new MockOracle(12e17);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, oracle);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        OpenEdenAccount implementation = new OpenEdenAccount(
            address(oracle), address(factory), TOKEN_COOLDOWN, address(hybond), address(express), cowSwapSettlement
        );
        factory.whitelist(address(implementation));

        bytes memory data = _initData(address(dai), address(hybond));
        vm.expectRevert(IOpenEdenAccount.InvalidAsset.selector);
        factory.create(1, address(this), data);
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

    function testSuperstateWriteOffReleasesSubAccountAndRescuesLateSettlement() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SuperstateAccount account = _deploySuperstate(uscc, usdc, oracle);

        uscc.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);
        account.sync(); // freezes the cohort rate at 11e18

        // no settlement: the receivable is written off, then sync releases the empty subaccount
        vm.warp(vm.getBlockTimestamp() + SETTLEMENT_DURATION);
        assertEq(account.totalAssets(), 0);
        assertEq(account.subAccounts(0), subAccount);

        account.sync();
        vm.expectRevert();
        account.subAccounts(0);

        // a late settlement is still rescueable and restores the value
        usdc.mint(subAccount, 11e6);
        account.rescueSubAccount(subAccount);

        assertEq(usdc.balanceOf(address(account)), 11e6);
        assertEq(account.totalAssets(), 11e6);
    }

    function testSuperstateDustDonationDoesNotReleaseSubAccount() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SuperstateAccount account = _deploySuperstate(uscc, usdc, oracle);

        uscc.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);

        // 1 wei donation pre-settlement stays isolated in the subaccount
        usdc.mint(subAccount, 1);
        account.sync();

        assertEq(account.subAccounts(0), subAccount);
        assertEq(usdc.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(subAccount), 1);
        assertEq(account.totalAssets(), 11e6);
    }

    function testSuperstateNeverFrozenWriteOffReleasesAndCanBeRescued() public {
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

        // a 1 wei donation after write-off is swept while the subaccount is released
        usdc.mint(subAccount, 1);
        account.sync();

        vm.expectRevert();
        account.subAccounts(0);
        assertEq(usdc.balanceOf(address(account)), 1);

        // a late full settlement is still rescued to the parent: funds recovered
        usdc.mint(subAccount, 11e6);
        account.rescueSubAccount(subAccount);

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

        // first tranche (60%): retained in the subaccount until coverage
        usdc.mint(subAccount, 6_600_000);
        account.sync();

        assertEq(account.subAccounts(0), subAccount);
        assertEq(usdc.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(subAccount), 6_600_000);
        assertEq(account.totalAssets(), 11e6);

        // second tranche (40%): coverage met, subaccount released
        usdc.mint(subAccount, 4_400_000);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 11e6);
        assertEq(usdc.balanceOf(subAccount), 0);
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

        // partial tranche: retained in the subaccount, no release
        usdc.mint(subAccount, 6_600_000);
        account.sync();

        // closing tranche: the full subaccount balance is swept and released
        usdc.mint(subAccount, 4_400_000);
        vm.expectEmit(true, true, true, true, address(account));
        emit ISettlementAccount.SweepSubAccount(subAccount, 11e6, 0);
        vm.expectEmit(true, true, true, true, address(account));
        emit ISettlementAccount.ReleaseSubAccount(subAccount);
        account.sync();
    }

    function testSecuritizeTransfersNoticeFromAccountAndTracksBucket() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle);

        acred.mint(address(account), 1e6);

        account.sync();

        (bool hasSubAccounts,) = address(account).staticcall(abi.encodeWithSignature("subAccounts(uint256)", 0));
        (uint256 amount, uint48 bucketIndex) = account.pendingCutoffs(0);
        (uint256 totalTokenToRedeem, uint256 pendingTokenToRedeem,) = account.buckets(bucketIndex);

        assertFalse(hasSubAccounts);
        assertEq(acred.balanceOf(address(account)), 0);
        assertEq(acred.balanceOf(redemptionWallet), 1e6); // plain transfer notice, no burn
        assertEq(amount, 1e6);
        assertEq(totalTokenToRedeem, 1e6);
        assertEq(pendingTokenToRedeem, 1e6);
        assertEq(account.totalAssets(), 11e6); // pending valued live
    }

    function testSecuritizeClearsBucketWhenSettlementReachesAccount() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle);

        acred.mint(address(account), 1e6);
        account.sync();
        _freezeSecuritize(account, oracle, 11e18);

        usdc.mint(address(account), 11e6);
        account.sync();

        (uint256 amount,) = account.pendingCutoffs(0);
        assertEq(amount, 0);
        assertEq(usdc.balanceOf(address(account)), 11e6);
        assertEq(account.totalAssets(), 11e6);
    }

    function testSecuritizeKeepsBucketPendingUntilSettlementCoversValue() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle);

        acred.mint(address(account), 1e6);
        account.sync();
        _freezeSecuritize(account, oracle, 11e18);

        usdc.mint(address(account), 10_999_999);
        account.sync();

        (uint256 amount,) = account.pendingCutoffs(0);
        assertEq(amount, 1e6);
        assertEq(account.totalAssets(), 11e6);

        usdc.mint(address(account), 1);
        account.sync();

        (amount,) = account.pendingCutoffs(0);
        assertEq(amount, 0);
        assertEq(usdc.balanceOf(address(account)), 11e6);
        assertEq(account.totalAssets(), 11e6);
    }

    function testSecuritizeWritesOffAfterPostCutoffWindow() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle, 0, 12 hours);

        acred.mint(address(account), 1e6);
        account.sync();

        // oracle never prints at/after the pricing date: written off without ever freezing
        vm.warp(account.bucketToTimestamp(account.currentBucket()) + 12 hours);
        assertEq(account.totalAssets(), 0);

        account.sync();

        (uint256 amount,) = account.pendingCutoffs(0);
        assertEq(amount, 0);
        assertEq(account.totalAssets(), 0);
    }

    function testSettlementAccountMigrationRevertsWithLiveSubAccountsAndSucceedsWhenEmpty() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        factory.whitelist(
            address(
                new SuperstateAccount(
                    address(oracle),
                    address(factory),
                    TOKEN_COOLDOWN,
                    address(uscc),
                    SETTLEMENT_DURATION,
                    cowSwapSettlement
                )
            )
        );
        SuperstateAccount account =
            SuperstateAccount(factory.create(1, address(this), _initData(address(usdc), address(uscc))));
        factory.whitelist(
            address(
                new SuperstateAccount(
                    address(oracle),
                    address(factory),
                    TOKEN_COOLDOWN,
                    address(uscc),
                    SETTLEMENT_DURATION,
                    cowSwapSettlement
                )
            )
        );

        // a live (in-flight) subaccount blocks migration
        uscc.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);

        vm.expectRevert(ISettlementAccount.MigrationWithLiveSubAccounts.selector);
        factory.migrate(address(account), 2, "");

        // full settlement releases the subaccount: migration succeeds from an empty pipeline
        account.sync(); // freezes the cohort rate at 11e18
        usdc.mint(subAccount, 11e6);
        account.sync();

        factory.migrate(address(account), 2, "");

        assertEq(account.version(), 2);
        assertEq(account.totalAssets(), 11e6);
    }

    function testSettlementAccountRescueSweepsLateSettlementOnReleasedSubAccount() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSuperstateToken uscc = new MockSuperstateToken();
        MockPriceDataOracle oracle = new MockPriceDataOracle(11e18);
        SuperstateAccount account = _deploySuperstate(uscc, usdc, oracle);

        uscc.mint(address(account), 1e6);
        account.sync();
        address subAccount = account.subAccounts(0);

        // a tracked subaccount is swept by sync, never by rescue
        vm.expectRevert(ISettlementAccount.SubAccountTracked.selector);
        account.rescueSubAccount(subAccount);

        // an address never created as a subaccount cannot be rescued
        vm.expectRevert(ISettlementAccount.UnknownSubAccount.selector);
        account.rescueSubAccount(makeAddr("stranger"));

        // full settlement releases the subaccount
        account.sync(); // freezes the cohort rate at 11e18
        usdc.mint(subAccount, 11e6);
        account.sync();
        vm.expectRevert();
        account.subAccounts(0);

        // a late settlement lands on the released subaccount: permissionless rescue sweeps it
        usdc.mint(subAccount, 5e5);
        vm.prank(makeAddr("rescuer"));
        account.rescueSubAccount(subAccount);

        assertEq(usdc.balanceOf(subAccount), 0);
        assertEq(usdc.balanceOf(address(account)), 11e6 + 5e5);
        assertEq(account.totalAssets(), 11e6 + 5e5);
    }

    function testSecuritizeFreezesCohortRateAfterPricingDate() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        SecuritizeAccount account = _deploySecuritize(acred, usdc, oracle, 5 days, 30 days);

        acred.mint(address(account), 1e6);

        account.sync();

        (, uint48 bucketIndex) = account.pendingCutoffs(0);
        uint48 cutoff = account.bucketToTimestamp(bucketIndex);
        assertEq(account.bucketToTimestamp(bucketIndex), cutoff);
        assertEq(account.totalAssets(), 1e6);

        // first oracle print at/after the pricing date freezes the cohort rate
        uint48 pricingTime = cutoff + 5 days;
        vm.warp(pricingTime + 1);
        oracle.setPriceData(1.2e18, pricingTime + 1);
        account.sync();

        oracle.setPriceData(2e18, uint48(vm.getBlockTimestamp()));
        assertEq(account.totalAssets(), 1_200_000);

        // unsettled past the settlement duration: written off
        vm.warp(cutoff + 30 days);
        assertEq(account.totalAssets(), 0);
    }

    function testAcredUsesPredeterminedCutoffsAndNoCooldown() public {
        vm.warp(1_781_654_400); // 2026-06-17 00:00:00 UTC

        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 acred = new MockERC20("Apollo Diversified Credit Securitize Fund", "ACRED", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        AcredSecuritizeAccount account = _deployAcredSecuritize(acred, usdc, oracle);

        assertEq(account.COOLDOWN(), 0);
        assertEq(account.bucketToTimestamp(0), 1_777_593_600);
        assertEq(account.bucketToTimestamp(1), 1_785_542_400);
        assertEq(account.bucketToTimestamp(account.currentBucket()), 1_785_542_400);

        acred.mint(address(account), 1e6);
        account.sync();

        (, uint48 bucketIndex) = account.pendingCutoffs(0);
        (uint256 totalTokenToRedeem, uint256 pendingTokenToRedeem,) = account.buckets(bucketIndex);
        assertEq(bucketIndex, 1);
        assertEq(totalTokenToRedeem, 1e6);
        assertEq(pendingTokenToRedeem, 1e6);

        acred.mint(address(account), 2e6);
        account.sync();

        (, bucketIndex) = account.pendingCutoffs(1);
        (totalTokenToRedeem, pendingTokenToRedeem,) = account.buckets(bucketIndex);
        assertEq(bucketIndex, 1);
        assertEq(totalTokenToRedeem, 3e6);
        assertEq(pendingTokenToRedeem, 3e6);
        assertEq(account.timestampToBucket(1_785_542_401), 2);
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

    function _deployOpenEden(MockERC20 hybond, MockERC20 asset, MockOracle oracle, MockOpenEdenExpress express)
        internal
        returns (OpenEdenAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        OpenEdenAccount implementation = new OpenEdenAccount(
            address(oracle), address(factory), TOKEN_COOLDOWN, address(hybond), address(express), cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = OpenEdenAccount(factory.create(1, address(this), _initData(address(asset), address(hybond))));
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
        account = _deploySecuritize(acred, asset, oracle, 0, SETTLEMENT_DURATION);
    }

    function _deploySecuritize(
        MockERC20 acred,
        MockERC20 asset,
        MockPriceDataOracle oracle,
        uint48 valuationDelay,
        uint48 settlementDuration
    ) internal returns (SecuritizeAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        AcredSecuritizeAccount implementation = new AcredSecuritizeAccount(
            address(oracle),
            address(factory),
            address(acred),
            redemptionWallet,
            valuationDelay,
            settlementDuration,
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = SecuritizeAccount(factory.create(1, address(this), _initData(address(asset), address(acred))));
    }

    function _freezeSecuritize(SecuritizeAccount account, MockPriceDataOracle oracle, uint256 price) internal {
        uint48 cutoff = account.bucketToTimestamp(account.currentBucket());
        vm.warp(cutoff);
        oracle.setPriceData(price, cutoff);
        account.sync();
    }

    function _deployAcredSecuritize(MockERC20 acred, MockERC20 asset, MockPriceDataOracle oracle)
        internal
        returns (AcredSecuritizeAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        AcredSecuritizeAccount implementation = new AcredSecuritizeAccount(
            address(oracle),
            address(factory),
            address(acred),
            redemptionWallet,
            4 days,
            SETTLEMENT_DURATION,
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = AcredSecuritizeAccount(factory.create(1, address(this), _initData(address(asset), address(acred))));
    }

    function _deployAsseto(MockAssetoToken tokenToRedeem, MockERC20 asset, address oracle, MockAssetoManager manager)
        internal
        returns (AssetoAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        AssetoAccount implementation = new AssetoAccount(
            oracle,
            address(factory),
            TOKEN_COOLDOWN,
            address(tokenToRedeem),
            address(manager),
            0,
            SETTLEMENT_DURATION,
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = AssetoAccount(
            factory.create(
                1,
                address(this),
                abi.encode(
                    IAssetoAccount.InitParams({
                        vault: address(_vault(asset)), adapter: adapter, offChainDestination: ASSETO_DESTINATION
                    })
                )
            )
        );
    }
}

contract MockAssetoToken is MockERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

    function burnFrom(address account, uint256 amount) external {
        uint256 allowance_ = allowance(account, msg.sender);
        if (allowance_ < type(uint256).max) {
            _approve(account, msg.sender, allowance_ - amount);
        }
        _burn(account, amount);
    }
}

contract MockAssetoPricer {
    struct PriceInfo {
        uint256 price;
        uint256 timestamp;
    }

    mapping(uint256 priceId => PriceInfo priceInfo) public prices;

    uint256 public latestPriceId;

    constructor(uint256 price, uint48 timestamp) {
        setPrice(1, price, timestamp);
    }

    function setPrice(uint256 priceId, uint256 price, uint48 timestamp) public {
        prices[priceId] = PriceInfo({price: price, timestamp: timestamp});
        latestPriceId = priceId;
    }

    function getLatestPrice() external view returns (uint256) {
        return prices[latestPriceId].price;
    }
}

contract MockAssetoManager {
    address public immutable rwa;
    address public immutable collateral;

    uint256 public immutable minimumRedemptionAmount;
    uint256 public immutable maximumRedemptionAmount;

    uint256 public redemptionRequestCounter;
    uint256 public lastAmount;
    bytes32 public lastOffChainDestination;

    event RedemptionRequestedServicedOffChain(
        address indexed user, bytes32 indexed redemptionId, uint256 rwaTokenAmountIn, bytes32 offChainDestination
    );

    constructor(address rwa_, address collateral_, uint256 minimumRedemptionAmount_, uint256 maximumRedemptionAmount_) {
        rwa = rwa_;
        collateral = collateral_;
        minimumRedemptionAmount = minimumRedemptionAmount_;
        maximumRedemptionAmount = maximumRedemptionAmount_;
    }

    function requestRedemptionServicedOffchain(uint256 amountRWATokenToRedeem, bytes32 offChainDestination) external {
        require(amountRWATokenToRedeem >= minimumRedemptionAmount);
        require(amountRWATokenToRedeem <= maximumRedemptionAmount);

        bytes32 redemptionId = bytes32(redemptionRequestCounter++);

        lastAmount = amountRWATokenToRedeem;
        lastOffChainDestination = offChainDestination;

        MockAssetoToken(rwa).burnFrom(msg.sender, amountRWATokenToRedeem);

        emit RedemptionRequestedServicedOffChain(msg.sender, redemptionId, amountRWATokenToRedeem, offChainDestination);
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

contract MockOpenEdenExpress {
    address public immutable token;
    address public immutable redeemAsset;
    address public immutable priceOracle;

    mapping(address account => uint256 amount) public pendingRedeemInfo;
    mapping(address account => uint256 amount) public redeemInfo;

    constructor(MockERC20 token_, MockERC20 redeemAsset_, MockOracle priceOracle_) {
        token = address(token_);
        redeemAsset = address(redeemAsset_);
        priceOracle = address(priceOracle_);
    }

    function previewRedeem(uint256 tokenAmount)
        external
        view
        returns (uint256 feeAmt, uint256 redeemAssetAmt, uint256 netRedeemAssetAmt)
    {
        redeemAssetAmt = tokenAmount * MockOracle(priceOracle).getPrice() / 1e30;
        feeAmt = redeemAssetAmt / 1000;
        netRedeemAssetAmt = redeemAssetAmt - feeAmt;
    }

    function requestRedeem(address to, uint256 tokenAmount) external {
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        pendingRedeemInfo[to] += tokenAmount;
    }

    function processPending(address account, uint256 tokenAmount) external {
        pendingRedeemInfo[account] -= tokenAmount;
        redeemInfo[account] += tokenAmount;
    }

    function processRedeem(address account, uint256 tokenAmount) external {
        (,, uint256 assets) = this.previewRedeem(tokenAmount);
        redeemInfo[account] -= tokenAmount;
        MockERC20(redeemAsset).mint(account, assets);
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

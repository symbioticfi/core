// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccountsBase, MockERC20, MockOracle, MockPriceDataOracle} from "./AccountsBase.t.sol";

import {AssetoAccount} from "../../../src/contracts/adapters/ll-adapter/AssetoAccount.sol";
import {AssetoOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/AssetoOracle.sol";
import {NoonAccount} from "../../../src/contracts/adapters/ll-adapter/NoonAccount.sol";
import {OpenEdenAccount} from "../../../src/contracts/adapters/ll-adapter/OpenEdenAccount.sol";
import {OpenEdenOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/OpenEdenOracle.sol";
import {
    AcredSecuritizeAccount,
    SecuritizeAccount
} from "../../../src/contracts/adapters/ll-adapter/SecuritizeAccount.sol";
import {SecuritizeNoticeAccount} from "../../../src/contracts/adapters/ll-adapter/SecuritizeNoticeAccount.sol";
import {SecuritizeOffRampAccount} from "../../../src/contracts/adapters/ll-adapter/SecuritizeOffRampAccount.sol";
import {SuperstateAccount} from "../../../src/contracts/adapters/ll-adapter/SuperstateAccount.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAssetoAccount} from "../../../src/interfaces/adapters/ll-adapter/asseto/IAssetoAccount.sol";
import {
    IOpenEdenAccount,
    MAX_REDEEM_QUEUE_LENGTH
} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenAccount.sol";
import {
    ISecuritizeNoticeAccount
} from "../../../src/interfaces/adapters/ll-adapter/securitize/ISecuritizeNoticeAccount.sol";
import {
    ISecuritizeOffRampAccount
} from "../../../src/interfaces/adapters/ll-adapter/securitize/ISecuritizeOffRampAccount.sol";
import {ISettlementAccount} from "../../../src/interfaces/adapters/ll-adapter/ISettlementAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProviderLegacySubAccounts {
    function subAccounts(uint256 index) external view returns (address subAccount);
}

contract ProviderAccountsTest is AccountsBase {
    bytes32 internal constant ASSETO_DESTINATION = bytes32("AoABT_red_test");
    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint48 internal constant SETTLEMENT_DURATION = 3 days;

    address internal redemptionWallet = makeAddr("redemptionWallet");

    function testAssetoOracleReadsLatestPriceData() public {
        MockAssetoPricer pricer = new MockAssetoPricer(975e18, uint48(vm.getBlockTimestamp()));
        AssetoOracle oracle = new AssetoOracle(1, type(uint256).max, address(pricer));

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
        AssetoAccount account =
            _deployAsseto(aoabt, usdc, address(new AssetoOracle(1, type(uint256).max, address(pricer))), manager);

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
        AssetoAccount account =
            _deployAsseto(aoabt, usdc, address(new AssetoOracle(1, type(uint256).max, address(pricer))), manager);

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
        AssetoAccount account =
            _deployAsseto(aoabt, usdc, address(new AssetoOracle(1, type(uint256).max, address(pricer))), manager);

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
        MockNoonSUSN susn = new MockNoonSUSN(usn, 12e17);
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

    function testOpenEdenRedeemQueueLimitIsThirty() public pure {
        assertEq(MAX_REDEEM_QUEUE_LENGTH, 30);
    }

    function testOpenEdenRequestsAndValuesQueuedRedeems() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        hybond.mint(address(account), 2 ether);

        (,, uint256 directPreviewAssets) = express.previewRedeem(2 ether);
        uint256 oracleScaledAssets = account.totalAssets();
        assertEq(directPreviewAssets, 2_398_799);
        assertEq(oracleScaledAssets, 2_398_800);
        assertEq(oracleScaledAssets - directPreviewAssets, 1);
        assertLe(oracleScaledAssets - directPreviewAssets, 1);

        account.sync();

        assertEq(hybond.balanceOf(address(account)), 0);
        assertEq(hybond.balanceOf(address(express)), 2 ether);
        assertEq(express.pendingRedeemInfo(address(account)), 2 ether);
        assertEq(account.totalAssets(), oracleScaledAssets);

        express.processPending(address(account), 1 ether);
        assertEq(account.totalAssets(), oracleScaledAssets);

        express.processRedeem(address(account), 1 ether);
        assertEq(usdc.balanceOf(address(account)), 1_199_400);
        assertEq(account.totalAssets(), 2_398_800);
    }

    function testOpenEdenRevertsRequestBelowExpressRedeemMinimum() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        express.setRedeemMinimum(100 ether);
        hybond.mint(address(account), 99 ether);

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "RedeemLessThanMinimum"));
        account.sync();

        assertEq(hybond.balanceOf(address(account)), 99 ether);
        assertEq(express.pendingRedeemInfo(address(account)), 0);

        hybond.mint(address(account), 1 ether);
        account.sync();

        assertEq(hybond.balanceOf(address(account)), 0);
        assertEq(express.pendingRedeemInfo(address(account)), 100 ether);
    }

    function testOpenEdenSupportsDifferentStableAssetAndCountsSettledRedemptionToken() public {
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdt, address(oracle), express);

        hybond.mint(address(account), 2 ether);
        assertEq(account.totalAssets(), 2_398_800);

        account.sync();
        assertEq(account.totalAssets(), 2_398_800);

        express.processPending(address(account), 1 ether);
        express.processRedeem(address(account), 1 ether);

        assertEq(usdc.balanceOf(address(account)), 1_199_400);
        assertEq(usdt.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 2_398_800);
    }

    function testOpenEdenUsesLockedFinalQueueValueBelowLimit() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        hybond.mint(address(account), 2 ether);
        account.sync();
        express.processPending(address(account), 2 ether);

        previewOracle.setPrice(15e17);

        assertEq(account.totalAssets(), 2_398_799);
    }

    function testOpenEdenReadsOnlyAccountEntriesBelowQueueLimit() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        for (uint256 i; i < MAX_REDEEM_QUEUE_LENGTH - 2; ++i) {
            express.addRedeemQueueEntry(makeAddr(string.concat("receiver", vm.toString(i))), 1 ether, 1e6, 1e3);
        }
        hybond.mint(address(account), 2 ether);
        account.sync();
        express.processPending(address(account), 2 ether);
        previewOracle.setPrice(15e17);

        assertEq(express.getRedeemQueueLength(), MAX_REDEEM_QUEUE_LENGTH - 1);
        assertEq(account.totalAssets(), 2_398_799);
    }

    function testOpenEdenFallsBackToRedeemInfoAtQueueLimit() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        for (uint256 i; i < MAX_REDEEM_QUEUE_LENGTH - 1; ++i) {
            express.addRedeemQueueEntry(makeAddr(string.concat("receiver", vm.toString(i))), 1 ether, 1e6, 1e3);
        }
        hybond.mint(address(account), 2 ether);
        account.sync();
        express.processPending(address(account), 2 ether);
        previewOracle.setPrice(15e17);

        assertEq(express.getRedeemQueueLength(), MAX_REDEEM_QUEUE_LENGTH);
        assertEq(account.totalAssets(), 2_997_000);
    }

    function testOpenEdenUsesOneOracleCallForPendingAndFallbackRedeems() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        for (uint256 i; i < MAX_REDEEM_QUEUE_LENGTH - 1; ++i) {
            express.addRedeemQueueEntry(makeAddr(string.concat("receiver", vm.toString(i))), 1 ether, 1e6, 1e3);
        }
        hybond.mint(address(account), 2 ether);
        account.sync();
        express.processPending(address(account), 1 ether);
        previewOracle.setPrice(15e17);

        vm.expectCall(address(oracle), abi.encodeWithSignature("getPrice()"), 1);
        assertEq(account.totalAssets(), 2_997_000);
    }

    function testOpenEdenPermissionlessRequestsRespectCooldown() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);
        address caller = makeAddr("caller");

        hybond.mint(address(account), 1 ether);
        vm.prank(caller);
        account.sync();

        hybond.mint(address(account), 1 ether);
        vm.warp(vm.getBlockTimestamp() + TOKEN_COOLDOWN - 1);
        vm.prank(caller);
        account.sync();

        assertEq(express.pendingRedeemInfo(address(account)), 1 ether);
        assertEq(hybond.balanceOf(address(account)), 1 ether);

        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(caller);
        account.sync();

        assertEq(express.pendingRedeemInfo(address(account)), 2 ether);
        assertEq(hybond.balanceOf(address(account)), 0);
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

        (bool hasSubAccounts,) =
            address(account).staticcall(abi.encodeCall(IProviderLegacySubAccounts.subAccounts, (0)));
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

    function testSecuritizeOffRampRedeemsFullBalanceWithQuotedMinimumAndClearsAllowance() public {
        MockERC20 rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
        MockERC20 vbill = new MockERC20("VanEck Treasury Fund", "VBILL", 6);
        MockSecuritizeOffRamp offRamp = new MockSecuritizeOffRamp(vbill, rlusd, 1e18, 1e18);
        SecuritizeOffRampAccount account = _deploySecuritizeOffRamp(vbill, rlusd, new MockOracle(1e18), offRamp);

        vbill.mint(address(account), 2e6);
        vm.expectCall(address(offRamp), abi.encodeCall(MockSecuritizeOffRamp.calculateLiquidityTokenAmount, (2e6)));
        account.sync();

        assertEq(vbill.balanceOf(address(account)), 0);
        assertEq(vbill.balanceOf(address(offRamp)), 2e6);
        assertEq(rlusd.balanceOf(address(account)), 2e18);
        assertEq(offRamp.lastAssetAmount(), 2e6);
        assertEq(offRamp.lastMinOutputAmount(), 2e18);
        assertEq(offRamp.allowanceDuringRedeem(), 2e6);
        assertEq(vbill.allowance(address(account), address(offRamp)), 0);
        assertEq(account.totalAssets(), 2e18);
    }

    function testSecuritizeOffRampRejectsQuoteBelowOracleValue() public {
        MockERC20 rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
        MockERC20 vbill = new MockERC20("VanEck Treasury Fund", "VBILL", 6);
        MockSecuritizeOffRamp offRamp = new MockSecuritizeOffRamp(vbill, rlusd, 0.95e18, 0.95e18);
        SecuritizeOffRampAccount account = _deploySecuritizeOffRamp(vbill, rlusd, new MockOracle(1e18), offRamp);

        vbill.mint(address(account), 2e6);

        vm.expectRevert(abi.encodeWithSelector(ISecuritizeOffRampAccount.InsufficientQuote.selector, 19e17, 2e18));
        account.sync();

        assertEq(vbill.balanceOf(address(account)), 2e6);
        assertEq(vbill.allowance(address(account), address(offRamp)), 0);
    }

    function testSecuritizeOffRampClearsResidualApproval() public {
        MockERC20 rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
        MockERC20 vbill = new MockERC20("VanEck Treasury Fund", "VBILL", 6);
        MockSecuritizeOffRamp offRamp = new MockSecuritizeOffRamp(vbill, rlusd, 1e18, 1e18);
        SecuritizeOffRampAccount account = _deploySecuritizeOffRamp(vbill, rlusd, new MockOracle(1e18), offRamp);
        offRamp.setSpendAmount(1e6);
        vbill.mint(address(account), 2e6);

        account.sync();

        assertEq(offRamp.allowanceDuringRedeem(), 2e6);
        assertEq(vbill.allowance(address(account), address(offRamp)), 0);
        assertEq(vbill.balanceOf(address(account)), 1e6);
        assertEq(rlusd.balanceOf(address(account)), 2e18);
    }

    function testSecuritizeOffRampRejectsUnderDeliveryAtomically() public {
        MockERC20 rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
        MockERC20 vbill = new MockERC20("VanEck Treasury Fund", "VBILL", 6);
        MockSecuritizeOffRamp offRamp = new MockSecuritizeOffRamp(vbill, rlusd, 1e18, 0.95e18);
        SecuritizeOffRampAccount account = _deploySecuritizeOffRamp(vbill, rlusd, new MockOracle(1e18), offRamp);

        vbill.mint(address(account), 2e6);
        rlusd.mint(address(account), 10e18); // proves the account checks the balance delta, not its absolute balance

        vm.expectRevert(abi.encodeWithSelector(ISecuritizeOffRampAccount.InsufficientOutput.selector, 19e17, 2e18));
        account.sync();

        assertEq(vbill.balanceOf(address(account)), 2e6);
        assertEq(rlusd.balanceOf(address(account)), 10e18);
        assertEq(vbill.allowance(address(account), address(offRamp)), 0);
    }

    function testSecuritizeOffRampRevalidatesMutableRoute() public {
        MockERC20 rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
        MockERC20 vbill = new MockERC20("VanEck Treasury Fund", "VBILL", 6);
        MockERC20 other = new MockERC20("Other", "OTHER", 6);
        MockSecuritizeOffRamp offRamp = new MockSecuritizeOffRamp(vbill, rlusd, 1e18, 1e18);
        SecuritizeOffRampAccount account = _deploySecuritizeOffRamp(vbill, rlusd, new MockOracle(1e18), offRamp);
        vbill.mint(address(account), 1e6);

        offRamp.setAssetAddress(address(other));
        vm.expectRevert(ISecuritizeOffRampAccount.InvalidTokenToRedeem.selector);
        account.sync();

        offRamp.setAssetAddress(address(vbill));
        offRamp.setLiquidityProvider(address(new MockSecuritizeLiquidityProvider(address(other))));
        vm.expectRevert(ISecuritizeOffRampAccount.InvalidAsset.selector);
        account.sync();

        assertEq(vbill.balanceOf(address(account)), 1e6);
        assertEq(vbill.allowance(address(account), address(offRamp)), 0);
    }

    function testSecuritizeNoticeSubmitsOneFrozenReceivableAndQueuesLaterTokens() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 stac = new MockERC20("Securitize Tokenized AAA CLO Fund", "STAC", 6);
        MockOracle oracle = new MockOracle(11e18);
        SecuritizeNoticeAccount account = _deploySecuritizeNotice(stac, usdc, oracle, SETTLEMENT_DURATION);
        uint48 requestTimestamp = uint48(vm.getBlockTimestamp());

        stac.mint(address(account), 1e6);
        account.sync();

        assertEq(stac.balanceOf(address(account)), 0);
        assertEq(stac.balanceOf(redemptionWallet), 1e6);
        assertEq(account.pendingAssets(), 11e6);
        assertEq(account.pendingExpiry(), requestTimestamp + SETTLEMENT_DURATION);
        assertEq(usdc.allowance(address(account), adapter), 0);
        assertEq(account.totalAssets(), 11e6);

        oracle.setPrice(13e18);
        stac.mint(address(account), 2e6);
        account.sync();

        assertEq(stac.balanceOf(address(account)), 2e6);
        assertEq(stac.balanceOf(redemptionWallet), 1e6);
        assertEq(account.pendingAssets(), 11e6);
        assertEq(account.totalAssets(), 37e6);
    }

    function testSecuritizeNoticeReconcilesSettlementWithoutDoubleCounting() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 stac = new MockERC20("Securitize Tokenized AAA CLO Fund", "STAC", 6);
        SecuritizeNoticeAccount account =
            _deploySecuritizeNotice(stac, usdc, new MockOracle(11e18), SETTLEMENT_DURATION);
        address receiver = makeAddr("settlementReceiver");

        stac.mint(address(account), 1e6);
        account.sync();

        usdc.mint(address(account), 6_600_000);
        assertEq(account.totalAssets(), 11e6);
        vm.prank(adapter);
        vm.expectRevert();
        usdc.transferFrom(address(account), receiver, 6_600_000);

        account.sync();

        assertEq(account.pendingAssets(), 4_400_000);
        assertEq(usdc.allowance(address(account), adapter), 6_600_000);
        assertEq(account.totalAssets(), 11e6);

        vm.prank(adapter);
        usdc.transferFrom(address(account), receiver, 6_600_000);
        assertEq(account.totalAssets(), 4_400_000);

        usdc.mint(address(account), 4_400_000);
        assertEq(account.totalAssets(), 4_400_000);
        account.sync();

        assertEq(account.pendingAssets(), 0);
        assertEq(account.pendingExpiry(), 0);
        assertEq(usdc.allowance(address(account), adapter), 4_400_000);
        assertEq(account.totalAssets(), 4_400_000);
    }

    function testSecuritizeNoticeSubmitsQueuedTokensAfterSettlement() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 stac = new MockERC20("Securitize Tokenized AAA CLO Fund", "STAC", 6);
        SecuritizeNoticeAccount account =
            _deploySecuritizeNotice(stac, usdc, new MockOracle(11e18), SETTLEMENT_DURATION);

        stac.mint(address(account), 1e6);
        account.sync();
        uint48 firstExpiry = account.pendingExpiry();
        stac.mint(address(account), 2e6);
        usdc.mint(address(account), 11e6);
        vm.warp(vm.getBlockTimestamp() + 1 days);

        account.sync();

        assertEq(stac.balanceOf(address(account)), 0);
        assertEq(stac.balanceOf(redemptionWallet), 3e6);
        assertEq(account.pendingAssets(), 22e6);
        assertEq(account.pendingExpiry(), uint48(vm.getBlockTimestamp()) + SETTLEMENT_DURATION);
        assertNotEq(account.pendingExpiry(), firstExpiry);
        assertEq(usdc.allowance(address(account), adapter), 11e6);
        assertEq(account.totalAssets(), 33e6);
    }

    function testSecuritizeNoticeWritesOffOnlyUnpaidResidual() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 stac = new MockERC20("Securitize Tokenized AAA CLO Fund", "STAC", 6);
        SecuritizeNoticeAccount account =
            _deploySecuritizeNotice(stac, usdc, new MockOracle(11e18), SETTLEMENT_DURATION);

        stac.mint(address(account), 1e6);
        account.sync();
        usdc.mint(address(account), 4e6);
        uint48 expiry = account.pendingExpiry();
        vm.warp(expiry - 1);
        assertEq(account.totalAssets(), 11e6);
        vm.warp(expiry);

        assertEq(account.totalAssets(), 4e6);
        vm.expectEmit(false, false, false, true, address(account));
        emit ISecuritizeNoticeAccount.ReconcileSettlement(4e6, 7e6);
        vm.expectEmit(false, false, false, true, address(account));
        emit ISecuritizeNoticeAccount.WriteOff(7e6);
        account.sync();

        assertEq(account.pendingAssets(), 0);
        assertEq(account.pendingExpiry(), 0);
        assertEq(usdc.allowance(address(account), adapter), 4e6);
        assertEq(account.totalAssets(), 4e6);
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

    function _deployOpenEden(MockERC20 hybond, MockERC20 asset, address oracle, MockOpenEdenExpress express)
        internal
        returns (OpenEdenAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        OpenEdenAccount implementation = new OpenEdenAccount(
            oracle, address(factory), TOKEN_COOLDOWN, address(hybond), address(express), cowSwapSettlement
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

    function _deploySecuritizeOffRamp(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        MockOracle oracle,
        MockSecuritizeOffRamp offRamp
    ) internal returns (SecuritizeOffRampAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        SecuritizeOffRampAccount implementation = new SecuritizeOffRampAccount(
            address(oracle),
            address(factory),
            address(tokenToRedeem),
            address(offRamp),
            address(asset),
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = SecuritizeOffRampAccount(
            factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem)))
        );
    }

    function _deploySecuritizeNotice(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        MockOracle oracle,
        uint48 settlementDuration
    ) internal returns (SecuritizeNoticeAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        SecuritizeNoticeAccount implementation = new SecuritizeNoticeAccount(
            address(oracle),
            address(factory),
            address(tokenToRedeem),
            redemptionWallet,
            settlementDuration,
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = SecuritizeNoticeAccount(
            factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem)))
        );
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
    uint256 internal immutable _assetsPerShare;

    constructor(MockERC20 asset_, uint256 assetsPerShare_) MockERC20("Staked USN", "sUSN", 18) {
        _asset = asset_;
        _assetsPerShare = assetsPerShare_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * _assetsPerShare / 1e18;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(owner == msg.sender);

        assets = convertToAssets(shares);
        _burn(owner, shares);
        _asset.mint(receiver, assets);
        MockNoonWithdrawalHandler(receiver).createWithdrawalRequest(owner, assets);
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

contract MockOpenEdenExpress {
    struct RedeemQueueEntry {
        address sender;
        address receiver;
        uint256 tokenAmount;
        uint256 shareAmount;
        uint256 redeemAssetAmt;
        uint256 feeAssetAmt;
        uint256 requestTimestamp;
        bytes32 id;
    }

    address public immutable token;
    address public immutable redeemAsset;
    address public immutable priceOracle;
    uint256 public redeemMinimum;

    mapping(address account => uint256 amount) public pendingRedeemInfo;
    mapping(address account => uint256 amount) public redeemInfo;
    RedeemQueueEntry[] internal redeemQueue;

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

    function setRedeemMinimum(uint256 minimum) external {
        redeemMinimum = minimum;
    }

    function requestRedeem(address to, uint256 tokenAmount) external {
        require(tokenAmount >= redeemMinimum, "RedeemLessThanMinimum");
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        pendingRedeemInfo[to] += tokenAmount;
    }

    function processPending(address account, uint256 tokenAmount) external {
        pendingRedeemInfo[account] -= tokenAmount;
        redeemInfo[account] += tokenAmount;
        (uint256 feeAmt, uint256 redeemAssetAmt,) = this.previewRedeem(tokenAmount);
        redeemQueue.push(
            RedeemQueueEntry({
                sender: account,
                receiver: account,
                tokenAmount: tokenAmount,
                shareAmount: 0,
                redeemAssetAmt: redeemAssetAmt,
                feeAssetAmt: feeAmt,
                requestTimestamp: block.timestamp,
                id: bytes32(redeemQueue.length)
            })
        );
    }

    function processRedeem(address account, uint256 tokenAmount) external {
        RedeemQueueEntry memory request = redeemQueue[0];
        require(request.receiver == account && request.tokenAmount == tokenAmount);
        for (uint256 i; i + 1 < redeemQueue.length; ++i) {
            redeemQueue[i] = redeemQueue[i + 1];
        }
        redeemQueue.pop();
        redeemInfo[account] -= tokenAmount;
        MockERC20(redeemAsset).mint(account, request.redeemAssetAmt - request.feeAssetAmt);
    }

    function addRedeemQueueEntry(address receiver, uint256 tokenAmount, uint256 redeemAssetAmt, uint256 feeAssetAmt)
        external
    {
        redeemInfo[receiver] += tokenAmount;
        redeemQueue.push(
            RedeemQueueEntry({
                sender: receiver,
                receiver: receiver,
                tokenAmount: tokenAmount,
                shareAmount: 0,
                redeemAssetAmt: redeemAssetAmt,
                feeAssetAmt: feeAssetAmt,
                requestTimestamp: block.timestamp,
                id: bytes32(redeemQueue.length)
            })
        );
    }

    function getRedeemQueueLength() external view returns (uint256) {
        return redeemQueue.length;
    }

    function getRedeemQueueInfo(uint256 index)
        external
        view
        returns (
            address sender,
            address receiver,
            uint256 tokenAmount,
            uint256 shareAmount,
            uint256 redeemAssetAmt,
            uint256 feeAssetAmt,
            uint256 requestTimestamp,
            bytes32 id
        )
    {
        RedeemQueueEntry memory request = redeemQueue[index];
        return (
            request.sender,
            request.receiver,
            request.tokenAmount,
            request.shareAmount,
            request.redeemAssetAmt,
            request.feeAssetAmt,
            request.requestTimestamp,
            request.id
        );
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

contract MockSecuritizeOffRamp {
    address public assetAddress;
    address public liquidityProvider;

    uint256 public quotePerWholeToken;
    uint256 public payoutPerWholeToken;
    uint256 public spendAmount;
    uint256 public lastAssetAmount;
    uint256 public lastMinOutputAmount;
    uint256 public allowanceDuringRedeem;

    constructor(MockERC20 tokenToRedeem_, MockERC20 liquidityToken_, uint256 quote_, uint256 payout_) {
        assetAddress = address(tokenToRedeem_);
        liquidityProvider = address(new MockSecuritizeLiquidityProvider(address(liquidityToken_)));
        quotePerWholeToken = quote_;
        payoutPerWholeToken = payout_;
    }

    function setAssetAddress(address assetAddress_) external {
        assetAddress = assetAddress_;
    }

    function setLiquidityProvider(address liquidityProvider_) external {
        liquidityProvider = liquidityProvider_;
    }

    function setSpendAmount(uint256 spendAmount_) external {
        spendAmount = spendAmount_;
    }

    function calculateLiquidityTokenAmount(uint256 assetAmount) external view returns (uint256) {
        return assetAmount * quotePerWholeToken / 1e6;
    }

    function redeem(uint256 assetAmount, uint256 minOutputAmount) external {
        require(assetAmount * quotePerWholeToken / 1e6 >= minOutputAmount);
        lastAssetAmount = assetAmount;
        lastMinOutputAmount = minOutputAmount;
        allowanceDuringRedeem = IERC20(assetAddress).allowance(msg.sender, address(this));
        IERC20(assetAddress).transferFrom(msg.sender, address(this), spendAmount == 0 ? assetAmount : spendAmount);
        MockERC20(MockSecuritizeLiquidityProvider(liquidityProvider).liquidityToken())
            .mint(msg.sender, assetAmount * payoutPerWholeToken / 1e6);
    }
}

contract MockSecuritizeLiquidityProvider {
    address public liquidityToken;

    constructor(address liquidityToken_) {
        liquidityToken = liquidityToken_;
    }
}

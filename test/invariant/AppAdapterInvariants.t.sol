// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AppAdapterInvariantHandler} from "./handlers/AppAdapterInvariantHandler.sol";

contract AppAdapterInvariantsTest is Test {
    AppAdapterInvariantHandler public handler;

    function setUp() public {
        handler = new AppAdapterInvariantHandler();

        bytes4[] memory selectors = new bytes4[](26);
        selectors[0] = AppAdapterInvariantHandler.deposit.selector;
        selectors[1] = AppAdapterInvariantHandler.mint.selector;
        selectors[2] = AppAdapterInvariantHandler.withdraw.selector;
        selectors[3] = AppAdapterInvariantHandler.redeem.selector;
        selectors[4] = AppAdapterInvariantHandler.transferShares.selector;
        selectors[5] = AppAdapterInvariantHandler.forceDeallocate.selector;
        selectors[6] = AppAdapterInvariantHandler.allocate.selector;
        selectors[7] = AppAdapterInvariantHandler.deallocate.selector;
        selectors[8] = AppAdapterInvariantHandler.requestRedeem.selector;
        selectors[9] = AppAdapterInvariantHandler.requestRedeemForReceiver.selector;
        selectors[10] = AppAdapterInvariantHandler.claim.selector;
        selectors[11] = AppAdapterInvariantHandler.fillQueue.selector;
        selectors[12] = AppAdapterInvariantHandler.sweepPending.selector;
        selectors[13] = AppAdapterInvariantHandler.setLimits.selector;
        selectors[14] = AppAdapterInvariantHandler.adapterDecreaseLimits.selector;
        selectors[15] = AppAdapterInvariantHandler.configureAdapter.selector;
        selectors[16] = AppAdapterInvariantHandler.setAutoAllocate.selector;
        selectors[17] = AppAdapterInvariantHandler.setVaultDepositControls.selector;
        selectors[18] = AppAdapterInvariantHandler.setVaultFees.selector;
        selectors[19] = AppAdapterInvariantHandler.accrueInterest.selector;
        selectors[20] = AppAdapterInvariantHandler.slash.selector;
        selectors[21] = AppAdapterInvariantHandler.release.selector;
        selectors[22] = AppAdapterInvariantHandler.observeCurrentStakeAt.selector;
        selectors[23] = AppAdapterInvariantHandler.quoteWithdrawable.selector;
        selectors[24] = AppAdapterInvariantHandler.warp.selector;
        selectors[25] = AppAdapterInvariantHandler.warpToBoundary.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SingleBlockStakeDoesNotDecreaseWithoutSlash() public view {
        handler.assertSingleBlockInvariant();
    }

    function invariant_ObservedGuaranteesSurviveUntilDurationOrSlash() public view {
        handler.assertCrossTimeInvariant();
    }

    function invariant_HistoryMatchesEndOfBlockStake() public view {
        handler.assertHistoryInvariant();
    }

    function invariant_AdapterDelegatorVaultAccountingMatches() public view {
        handler.assertAccountingInvariant();
    }

    function invariant_QueueAccountingMatchesLiquidity() public view {
        handler.assertQueueInvariant();
    }
}

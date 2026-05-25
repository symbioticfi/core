// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AppAdapterInvariantHandler} from "./handlers/AppAdapterInvariantHandler.sol";

contract AppAdapterInvariantsTest is Test {
    AppAdapterInvariantHandler public handler;

    function setUp() public {
        handler = new AppAdapterInvariantHandler();

        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = AppAdapterInvariantHandler.deposit.selector;
        selectors[1] = AppAdapterInvariantHandler.forceDeallocate.selector;
        selectors[2] = AppAdapterInvariantHandler.allocate.selector;
        selectors[3] = AppAdapterInvariantHandler.deallocate.selector;
        selectors[4] = AppAdapterInvariantHandler.requestRedeem.selector;
        selectors[5] = AppAdapterInvariantHandler.claim.selector;
        selectors[6] = AppAdapterInvariantHandler.sweepPending.selector;
        selectors[7] = AppAdapterInvariantHandler.setLimits.selector;
        selectors[8] = AppAdapterInvariantHandler.configureAdapter.selector;
        selectors[9] = AppAdapterInvariantHandler.setAutoAllocate.selector;
        selectors[10] = AppAdapterInvariantHandler.slash.selector;
        selectors[11] = AppAdapterInvariantHandler.observeCurrentStakeAt.selector;
        selectors[12] = AppAdapterInvariantHandler.warp.selector;
        selectors[13] = AppAdapterInvariantHandler.warpToBoundary.selector;

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

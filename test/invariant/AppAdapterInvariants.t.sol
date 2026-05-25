// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AppAdapterInvariantHandler} from "./handlers/AppAdapterInvariantHandler.sol";

contract AppAdapterInvariantsTest is Test {
    AppAdapterInvariantHandler public handler;

    function setUp() public {
        handler = new AppAdapterInvariantHandler();

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = AppAdapterInvariantHandler.deposit.selector;
        selectors[1] = AppAdapterInvariantHandler.forceDeallocate.selector;
        selectors[2] = AppAdapterInvariantHandler.requestRedeem.selector;
        selectors[3] = AppAdapterInvariantHandler.claim.selector;
        selectors[4] = AppAdapterInvariantHandler.sweepPending.selector;
        selectors[5] = AppAdapterInvariantHandler.setLimits.selector;
        selectors[6] = AppAdapterInvariantHandler.slash.selector;
        selectors[7] = AppAdapterInvariantHandler.observeCurrentStakeAt.selector;
        selectors[8] = AppAdapterInvariantHandler.warp.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SingleBlockStakeDoesNotDecreaseWithoutSlash() public view {
        handler.assertSingleBlockInvariant();
    }

    function invariant_ObservedGuaranteesSurviveUntilDurationOrSlash() public view {
        handler.assertCrossTimeInvariant();
    }

    function invariant_AdapterDelegatorVaultAccountingMatches() public view {
        handler.assertAccountingInvariant();
    }

    function invariant_QueueAccountingMatchesLiquidity() public view {
        handler.assertQueueInvariant();
    }
}

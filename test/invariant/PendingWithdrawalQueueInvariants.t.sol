// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {PendingWithdrawalQueueHandler} from "./handlers/PendingWithdrawalQueueHandler.sol";

contract PendingWithdrawalQueueInvariantsTest is Test {
    PendingWithdrawalQueueHandler public handler;

    function setUp() public {
        handler = new PendingWithdrawalQueueHandler();

        bytes4[] memory selectors = new bytes4[](16);
        selectors[0] = PendingWithdrawalQueueHandler.depositWhilePending.selector;
        selectors[1] = PendingWithdrawalQueueHandler.allocateWhilePending.selector;
        selectors[2] = PendingWithdrawalQueueHandler.allocateAllWhilePending.selector;
        selectors[3] = PendingWithdrawalQueueHandler.withdrawWhilePending.selector;
        selectors[4] = PendingWithdrawalQueueHandler.redeemWhilePending.selector;
        selectors[5] = PendingWithdrawalQueueHandler.mintWhilePending.selector;
        selectors[6] = PendingWithdrawalQueueHandler.forceDeallocateWhilePending.selector;
        selectors[7] = PendingWithdrawalQueueHandler.deallocateWhilePending.selector;
        selectors[8] = PendingWithdrawalQueueHandler.deallocateAllWhilePending.selector;
        selectors[9] = PendingWithdrawalQueueHandler.deallocateExactWhilePending.selector;
        selectors[10] = PendingWithdrawalQueueHandler.requestRedeemWhilePending.selector;
        selectors[11] = PendingWithdrawalQueueHandler.fillQueueWhilePending.selector;
        selectors[12] = PendingWithdrawalQueueHandler.claimQueueWhilePending.selector;
        selectors[13] = PendingWithdrawalQueueHandler.sweepPendingWhilePending.selector;
        selectors[14] = PendingWithdrawalQueueHandler.setLimitsWhilePending.selector;
        selectors[15] = PendingWithdrawalQueueHandler.setAutoAllocateWhilePending.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_NoAllocationWhileWithdrawalQueueHasPendingAssets() public view {
        assertEq(handler.allocatedWhilePending(), 0);
    }

    function invariant_NoInstantWithdrawalWhileWithdrawalQueueHasPendingAssets() public view {
        assertEq(handler.withdrawnWhilePending(), 0);
    }
}

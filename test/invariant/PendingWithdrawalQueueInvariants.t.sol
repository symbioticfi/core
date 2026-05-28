// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {PendingWithdrawalQueueHandler} from "./handlers/PendingWithdrawalQueueHandler.sol";

contract PendingWithdrawalQueueInvariantsTest is Test {
    PendingWithdrawalQueueHandler public handler;

    function setUp() public {
        handler = new PendingWithdrawalQueueHandler();

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PendingWithdrawalQueueHandler.depositWhilePending.selector;
        selectors[1] = PendingWithdrawalQueueHandler.allocateWhilePending.selector;
        selectors[2] = PendingWithdrawalQueueHandler.allocateAllWhilePending.selector;
        selectors[3] = PendingWithdrawalQueueHandler.withdrawWhilePending.selector;
        selectors[4] = PendingWithdrawalQueueHandler.redeemWhilePending.selector;

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

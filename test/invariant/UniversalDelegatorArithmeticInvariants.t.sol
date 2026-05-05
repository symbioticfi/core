// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {UniversalDelegatorArithmeticHandler} from "./handlers/UniversalDelegatorArithmeticHandler.sol";

contract UniversalDelegatorArithmeticInvariantsTest is StdInvariant, Test {
    UniversalDelegatorArithmeticHandler internal handler;

    function setUp() public {
        handler = new UniversalDelegatorArithmeticHandler();

        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = UniversalDelegatorArithmeticHandler.deposit.selector;
        selectors[1] = UniversalDelegatorArithmeticHandler.withdraw.selector;
        selectors[2] = UniversalDelegatorArithmeticHandler.createRootSlot.selector;
        selectors[3] = UniversalDelegatorArithmeticHandler.setMaxNetworkLimit.selector;
        selectors[4] = UniversalDelegatorArithmeticHandler.createNetworkSlot.selector;
        selectors[5] = UniversalDelegatorArithmeticHandler.createOperatorSlot.selector;
        selectors[6] = UniversalDelegatorArithmeticHandler.setSize.selector;
        selectors[7] = UniversalDelegatorArithmeticHandler.swapSlots.selector;
        selectors[8] = UniversalDelegatorArithmeticHandler.removeSlot.selector;
        selectors[9] = UniversalDelegatorArithmeticHandler.resetAllocation.selector;
        selectors[10] = UniversalDelegatorArithmeticHandler.slash.selector;
        selectors[11] = UniversalDelegatorArithmeticHandler.touchMaturedDecreaseThenIncreaseSameBlock.selector;
        selectors[12] = UniversalDelegatorArithmeticHandler.sameBlockDelayedDecrease.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_StakeForDurationsStayCapacityBounded() public view {
        handler.assertStakeForDurationAndCapacityInvariants();
    }

    function invariant_NetworkOperatorSlotsStayIsolated() public view {
        handler.assertTrackedSlotAssignmentsIsolated();
    }

    function invariant_SameBlockStakeViewsNeverDecrease() public {
        handler.assertSameBlockStakeViewsNonDecreasing();
    }

    function invariant_StakeForPromisesHoldAcrossTime() public view {
        handler.assertTemporalStakeForPromisesHold();
    }

    function invariant_HistoricalStakeForAtCapacityBounded() public view {
        handler.assertHistoricalStakeForAtCapacityInvariants();
    }

    function invariant_HistoricalStakeForAtObservationsStayExact() public view {
        handler.assertHistoricalStakeForAtObservationsExact();
    }

    function invariant_SyncedSizeSumsMatchSubnetworkTotals() public view {
        handler.assertSyncedSizeSumsMatchTotals();
    }

    function invariant_HandlerActionsDoNotUnexpectedlyRevert() public view {
        handler.assertNoUnexpectedActionReverts();
    }
}

contract UniversalDelegatorHistoricalStakeForAtInvariantsTest is StdInvariant, Test {
    UniversalDelegatorArithmeticHandler internal handler;

    function setUp() public {
        handler = new UniversalDelegatorArithmeticHandler();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UniversalDelegatorArithmeticHandler.touchMaturedDecreaseThenIncreaseSameBlock.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_HistoricalStakeForAtObservationsStayExact() public view {
        handler.assertHistoricalStakeForAtObservationsExact();
    }
}

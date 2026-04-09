// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {
    UniversalDelegatorArithmeticHandler,
    UniversalDelegatorArithmeticHarness
} from "./handlers/UniversalDelegatorArithmeticHandler.sol";

import {CoreV2StakeForInvariantHelper} from "../helpers/CoreV2StakeForInvariantHelper.sol";

import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {
    IUniversalDelegator,
    WITHDRAWAL_BUFFER_CHILD_INDEX
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";

contract UniversalDelegatorArithmeticInvariantsTest is StdInvariant, Test, CoreV2StakeForInvariantHelper {
    using UniversalDelegatorIndex for uint96;

    struct CurrentParentState {
        uint208 expectedPrevSize;
        uint208 expectedPrevPending0;
        uint208 expectedPrevPendingHalf;
        uint208 expectedPrevPendingMax;
        uint32 childIndex;
        uint32 lastSeenChild;
        uint256 visited;
        bool sharedParent;
    }

    UniversalDelegatorArithmeticHandler internal handler;

    function setUp() public {
        handler = new UniversalDelegatorArithmeticHandler();

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = UniversalDelegatorArithmeticHandler.warp.selector;
        selectors[1] = UniversalDelegatorArithmeticHandler.deposit.selector;
        selectors[2] = UniversalDelegatorArithmeticHandler.withdraw.selector;
        selectors[3] = UniversalDelegatorArithmeticHandler.createRootSlot.selector;
        selectors[4] = UniversalDelegatorArithmeticHandler.setMaxNetworkLimit.selector;
        selectors[5] = UniversalDelegatorArithmeticHandler.createNetworkSlot.selector;
        selectors[6] = UniversalDelegatorArithmeticHandler.createOperatorSlot.selector;
        selectors[7] = UniversalDelegatorArithmeticHandler.setSize.selector;
        selectors[8] = UniversalDelegatorArithmeticHandler.swapSlots.selector;
        selectors[9] = UniversalDelegatorArithmeticHandler.removeSlot.selector;
        selectors[10] = UniversalDelegatorArithmeticHandler.resetAllocation.selector;
        selectors[11] = UniversalDelegatorArithmeticHandler.slash.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_CurrentCursorsNeverExceedCumulative() public view {
        UniversalDelegatorArithmeticHarness delegator = handler.delegator();
        uint96[] memory trackedSlots = handler.getTrackedSlots();

        for (uint256 i; i < trackedSlots.length; ++i) {
            uint96 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists) {
                continue;
            }

            assertLe(delegator.exposePendingCursor(slot), delegator.slotPendingCumulativeLatest(slot));

            if (slot.getDepth() == 2) {
                uint96 parent = slot.getParentIndex();
                if (delegator.getSlot(parent).exists && delegator.getSlot(parent).isShared) {
                    assertLe(
                        delegator.exposeSharedPendingCursor(slot), delegator.slotClearedPendingCursorLatest(parent)
                    );
                    assertLe(
                        delegator.exposeSharedSizeCursor(slot), delegator.slotSharedSizeConsumedCumulativeLatest(parent)
                    );
                }
            }
        }

        assertLe(delegator.exposeNoAdaptersPendingCursor(), delegator.noAdaptersPendingCumulativeLatest());
    }

    function invariant_RootStakeForSumsStayWithinVaultCapacity() public view {
        UniversalDelegatorArithmeticHarness delegator = handler.delegator();
        IVaultV2 vault = handler.vault();
        uint96[] memory liveRoots = _liveTracked(handler.getTrackedRootSlots(), delegator);

        _assertStakeForInvariantForDurations(address(vault), address(delegator), liveRoots, vault.epochDuration());
    }

    function invariant_CurrentFilledEqualsTrackedChildSums() public view {
        UniversalDelegatorArithmeticHarness delegator = handler.delegator();
        IVaultV2 vault = handler.vault();
        uint48 epochDuration = vault.epochDuration();
        uint96[] memory roots = handler.getTrackedRootSlots();
        uint96[] memory networks = handler.getTrackedNetworkSlots();
        _assertCurrentFilledMatchesTrackedChildren(delegator, 0, epochDuration);

        for (uint256 i; i < roots.length; ++i) {
            if (!delegator.getSlot(roots[i]).exists) {
                continue;
            }
            _assertCurrentFilledMatchesTrackedChildren(delegator, roots[i], epochDuration);
        }

        for (uint256 i; i < networks.length; ++i) {
            if (!delegator.getSlot(networks[i]).exists) {
                continue;
            }
            _assertCurrentFilledMatchesTrackedChildren(delegator, networks[i], epochDuration);
        }
    }

    function invariant_CurrentParentPrefixSumsAndLinkedListsStayConsistent() public view {
        UniversalDelegatorArithmeticHarness delegator = handler.delegator();
        uint48 epochDuration = handler.vault().epochDuration();
        uint96[] memory roots = handler.getTrackedRootSlots();
        uint96[] memory networks = handler.getTrackedNetworkSlots();

        _assertCurrentParentState(delegator, 0, epochDuration);

        for (uint256 i; i < roots.length; ++i) {
            if (!delegator.getSlot(roots[i]).exists) {
                continue;
            }
            _assertCurrentParentState(delegator, roots[i], epochDuration);
        }

        for (uint256 i; i < networks.length; ++i) {
            if (!delegator.getSlot(networks[i]).exists) {
                continue;
            }
            _assertCurrentParentState(delegator, networks[i], epochDuration);
        }
    }

    function invariant_NoAdaptersAggregateMatchesLiveRoots() public view {
        UniversalDelegatorArithmeticHarness delegator = handler.delegator();
        uint96[] memory roots = handler.getTrackedRootSlots();
        uint256 expected;

        for (uint256 i; i < roots.length; ++i) {
            IUniversalDelegator.Slot memory slot = delegator.getSlot(roots[i]);
            if (!slot.exists || !slot.noAdapters) {
                continue;
            }

            expected += uint256(slot.size) + delegator.getPending(roots[i], 0);
        }

        assertEq(delegator.getNoAdaptersSize(), expected);
    }

    function invariant_NonSharedParentsNeverOverfillCapacity() public view {
        UniversalDelegatorArithmeticHarness delegator = handler.delegator();
        IVaultV2 vault = handler.vault();
        uint48 epochDuration = vault.epochDuration();
        uint96[] memory roots = handler.getTrackedRootSlots();
        uint96[] memory networks = handler.getTrackedNetworkSlots();
        _assertNonSharedParentCapacity(delegator, 0, epochDuration);

        for (uint256 i; i < roots.length; ++i) {
            if (!delegator.getSlot(roots[i]).exists) {
                continue;
            }
            _assertNonSharedParentCapacity(delegator, roots[i], epochDuration);
        }

        for (uint256 i; i < networks.length; ++i) {
            if (!delegator.getSlot(networks[i]).exists) {
                continue;
            }
            _assertNonSharedParentCapacity(delegator, networks[i], epochDuration);
        }
    }

    function invariant_HistoricalSamplesStayConsistent() public view {
        UniversalDelegatorArithmeticHarness delegator = handler.delegator();
        IVaultV2 vault = handler.vault();
        uint48 epochDuration = vault.epochDuration();
        uint48[] memory timestamps = _sampledTimestamps();
        uint96[] memory roots = handler.getTrackedRootSlots();
        uint96[] memory networks = handler.getTrackedNetworkSlots();
        uint96[] memory allSlots = handler.getTrackedSlots();

        for (uint256 i; i < timestamps.length; ++i) {
            uint48 timestamp = timestamps[i];
            _assertHistoricalFilledMatchesTrackedChildren(delegator, 0, epochDuration, timestamp);

            for (uint256 j; j < roots.length; ++j) {
                _assertHistoricalFilledMatchesTrackedChildren(delegator, roots[j], epochDuration, timestamp);
            }

            for (uint256 j; j < networks.length; ++j) {
                _assertHistoricalFilledMatchesTrackedChildren(delegator, networks[j], epochDuration, timestamp);
            }

            for (uint256 j; j < allSlots.length; ++j) {
                uint96 slot = allSlots[j];
                _assertHistoricalPendingBounds(delegator, slot, epochDuration, timestamp);
            }
        }
    }

    function _assertCurrentFilledMatchesTrackedChildren(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 parent,
        uint48 epochDuration
    ) internal view {
        for (uint256 i; i < 3; ++i) {
            uint48 duration = _durationAt(i, epochDuration);
            assertEq(delegator.getFilled(parent, duration), _sumCurrentChildAllocations(delegator, parent, duration));
        }
    }

    function _assertHistoricalFilledMatchesTrackedChildren(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 parent,
        uint48 epochDuration,
        uint48 timestamp
    ) internal view {
        for (uint256 i; i < 3; ++i) {
            uint48 duration = _durationAt(i, epochDuration);
            uint256 filledAt = delegator.getFilledAt(parent, duration, timestamp);
            uint256 summed = _sumHistoricalChildAllocations(delegator, parent, duration, timestamp);
            assertEq(filledAt, summed);

            if (!_isSharedParent(delegator, parent)) {
                assertLe(filledAt, delegator.getBalanceAt(parent, duration, timestamp));
            }
        }
    }

    function _assertHistoricalPendingBounds(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 slot,
        uint48 epochDuration,
        uint48 timestamp
    ) internal view {
        for (uint256 i; i < 3; ++i) {
            uint48 duration = _durationAt(i, epochDuration);
            uint208 pendingAt = delegator.getPendingAt(slot, duration, timestamp);
            assertLe(pendingAt, delegator.slotPendingCumulativeAt(slot, timestamp));

            if (slot > 0) {
                assertLe(
                    delegator.getAllocatedAt(slot, duration, timestamp),
                    delegator.getBalanceAt(slot.getParentIndex(), duration, timestamp)
                );
                assertLe(
                    delegator.getAllocatedAt(slot, duration, timestamp),
                    uint256(delegator.slotSizeAt(slot, timestamp)) + pendingAt
                );
            }
        }
    }

    function _assertCurrentParentState(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 parent,
        uint48 epochDuration
    ) internal view {
        IUniversalDelegator.Slot memory parentSlot = delegator.getSlot(parent);
        uint48 halfDuration = epochDuration / 2;
        uint48 maxDuration = epochDuration - 1;
        CurrentParentState memory state = CurrentParentState({
            expectedPrevSize: 0,
            expectedPrevPending0: 0,
            expectedPrevPendingHalf: 0,
            expectedPrevPendingMax: 0,
            childIndex: parentSlot.firstChild,
            lastSeenChild: 0,
            visited: 0,
            sharedParent: _isSharedParent(delegator, parent)
        });
        uint32[] memory seenChildIndexes =
            new uint32[](parent == 0 ? 1 + handler.getTrackedRootSlots().length : parent.getDepth() == 1 ? 32 : 32);

        while (state.childIndex > 0 && state.childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX) {
            uint96 child = parent.createIndex(state.childIndex);
            IUniversalDelegator.Slot memory childSlot = delegator.getSlot(child);

            assertTrue(childSlot.exists);
            assertEq(child.getParentIndex(), parent);
            assertTrue(child.getChildIndex() != WITHDRAWAL_BUFFER_CHILD_INDEX);

            for (uint256 i; i < state.visited; ++i) {
                assertTrue(seenChildIndexes[i] != state.childIndex);
            }
            seenChildIndexes[state.visited] = state.childIndex;

            if (state.sharedParent) {
                _assertSharedParentPrefixState(delegator, child, childSlot, halfDuration, maxDuration);
            } else {
                _assertNonSharedParentPrefixState(
                    delegator,
                    child,
                    childSlot,
                    state.expectedPrevSize,
                    state.expectedPrevPending0,
                    state.expectedPrevPendingHalf,
                    state.expectedPrevPendingMax,
                    halfDuration,
                    maxDuration
                );
                state.expectedPrevPending0 += uint208(delegator.getPending(child, 0));
                state.expectedPrevPendingHalf += uint208(delegator.getPending(child, halfDuration));
                state.expectedPrevPendingMax += uint208(delegator.getPending(child, maxDuration));
            }

            state.expectedPrevSize += childSlot.size;
            state.lastSeenChild = state.childIndex;
            state.childIndex = childSlot.nextSlot;
            ++state.visited;
        }

        assertEq(parentSlot.existChildren, state.visited);

        if (state.visited == 0) {
            assertEq(parentSlot.firstChild, 0);
            assertEq(parentSlot.lastChild, 0);
            return;
        }

        assertEq(parentSlot.lastChild, state.lastSeenChild);
    }

    function _assertSharedParentPrefixState(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 child,
        IUniversalDelegator.Slot memory childSlot,
        uint48 halfDuration,
        uint48 maxDuration
    ) internal view {
        assertEq(childSlot.prevSizeSum, 0);
        assertEq(delegator.exposeGetPrevPendingSum(child, 0), 0);
        assertEq(delegator.exposeGetPrevPendingSum(child, halfDuration), 0);
        assertEq(delegator.exposeGetPrevPendingSum(child, maxDuration), 0);
    }

    function _assertNonSharedParentPrefixState(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 child,
        IUniversalDelegator.Slot memory childSlot,
        uint208 expectedPrevSize,
        uint208 expectedPrevPending0,
        uint208 expectedPrevPendingHalf,
        uint208 expectedPrevPendingMax,
        uint48 halfDuration,
        uint48 maxDuration
    ) internal view {
        assertEq(childSlot.prevSizeSum, expectedPrevSize);
        assertEq(delegator.exposeGetPrevPendingSum(child, 0), expectedPrevPending0);
        assertEq(delegator.exposeGetPrevPendingSum(child, halfDuration), expectedPrevPendingHalf);
        assertEq(delegator.exposeGetPrevPendingSum(child, maxDuration), expectedPrevPendingMax);
    }

    function _assertNonSharedParentCapacity(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 parent,
        uint48 epochDuration
    ) internal view {
        if (_isSharedParent(delegator, parent)) {
            return;
        }

        for (uint256 i; i < 3; ++i) {
            uint48 duration = _durationAt(i, epochDuration);
            assertLe(_sumCurrentChildAllocations(delegator, parent, duration), delegator.getBalance(parent, duration));
        }
    }

    function _sumCurrentChildAllocations(UniversalDelegatorArithmeticHarness delegator, uint96 parent, uint48 duration)
        internal
        view
        returns (uint256 total)
    {
        uint32 childIndex = delegator.getSlot(parent).firstChild;
        uint256 maxChildren = handler.getTrackedSlots().length + 1;

        for (uint256 visited; childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX; ++visited) {
            assertLt(visited, maxChildren);

            uint96 child = parent.createIndex(childIndex);
            total += delegator.getAllocated(child, duration);
            childIndex = delegator.getSlot(child).nextSlot;
        }
    }

    function _sumHistoricalChildAllocations(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 parent,
        uint48 duration,
        uint48 timestamp
    ) internal view returns (uint256 total) {
        uint32 childIndex = delegator.slotFirstChildAt(parent, timestamp);
        uint256 maxChildren = handler.getTrackedSlots().length + 1;

        for (uint256 visited; childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX; ++visited) {
            assertLt(visited, maxChildren);

            uint96 child = parent.createIndex(childIndex);
            total += delegator.getAllocatedAt(child, duration, timestamp);
            childIndex = delegator.slotNextSlotAt(child, timestamp);
        }
    }

    function _liveTracked(uint96[] memory tracked, UniversalDelegatorArithmeticHarness delegator)
        internal
        view
        returns (uint96[] memory liveTracked)
    {
        uint96[] memory scratch = new uint96[](tracked.length);
        uint256 count;
        for (uint256 i; i < tracked.length; ++i) {
            if (!delegator.getSlot(tracked[i]).exists) {
                continue;
            }
            scratch[count++] = tracked[i];
        }

        liveTracked = new uint96[](count);
        for (uint256 i; i < count; ++i) {
            liveTracked[i] = scratch[i];
        }
    }

    function _sampledTimestamps() internal view returns (uint48[] memory timestamps) {
        uint48[] memory tracked = handler.getTrackedTimestamps();
        timestamps = new uint48[](tracked.length + 3);
        timestamps[0] = 0;
        timestamps[1] = 1;
        timestamps[2] = 2;
        for (uint256 i; i < tracked.length; ++i) {
            timestamps[i + 3] = tracked[i];
        }
    }

    function _isSharedParent(UniversalDelegatorArithmeticHarness delegator, uint96 parent)
        internal
        view
        returns (bool)
    {
        return parent.getDepth() == 1 && delegator.getSlot(parent).isShared;
    }

    function _durationAt(uint256 index, uint48 epochDuration) internal pure returns (uint48) {
        if (index == 0) {
            return 0;
        }
        if (index == 1) {
            return epochDuration / 2;
        }
        return epochDuration - 1;
    }
}

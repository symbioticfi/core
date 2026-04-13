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

    uint256 internal constant SLOT_MAPPING_SLOT = 2;
    uint256 internal constant SLOT_TRACE_SIZE_OFFSET = 1;
    uint256 internal constant SLOT_TRACE_NEXT_SLOT_OFFSET = 2;
    uint256 internal constant SLOT_TRACE_LAST_CHILD_OFFSET = 3;
    uint256 internal constant SLOT_TRACE_FIRST_CHILD_OFFSET = 4;
    uint256 internal constant SLOT_TRACE_PENDING_CUMULATIVE_OFFSET = 7;
    uint256 internal constant SLOT_TRACE_CLEARED_PENDING_CURSOR_OFFSET = 8;
    uint256 internal constant SLOT_TRACE_SHARED_PENDING_CONSUMED_OFFSET = 9;
    uint256 internal constant SLOT_TRACE_SHARED_SIZE_CONSUMED_OFFSET = 10;
    uint256 internal constant NO_ADAPTERS_PENDING_CUMULATIVE_SLOT = 7;
    uint256 internal constant CLEARED_NO_ADAPTERS_PENDING_CURSOR_SLOT = 8;
    uint256 internal constant CHILDREN_PENDING_AT_OFFSET_BYTES = 15;

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
        uint48 epochDuration = handler.vault().epochDuration();
        uint96[] memory trackedSlots = handler.getTrackedSlots();

        for (uint256 i; i < trackedSlots.length; ++i) {
            uint96 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists) {
                continue;
            }

            assertLe(_pendingCursor(delegator, slot, epochDuration), _slotPendingCumulativeLatest(delegator, slot));

            if (slot.getDepth() == 2) {
                uint96 parent = slot.getParentIndex();
                if (delegator.getSlot(parent).exists && delegator.getSlot(parent).isShared) {
                    assertLe(
                        _sharedPendingCursor(delegator, slot, epochDuration),
                        _slotClearedPendingCursorLatest(delegator, parent)
                    );
                    assertLe(
                        _sharedSizeCursor(delegator, slot, epochDuration),
                        _slotSharedSizeConsumedCumulativeLatest(delegator, parent)
                    );
                }
            }
        }

        assertLe(_noAdaptersPendingCursor(delegator, epochDuration), _noAdaptersPendingCumulativeLatest(delegator));
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
            assertLe(pendingAt, _slotPendingCumulativeAt(delegator, slot, timestamp));

            if (slot > 0) {
                assertLe(
                    delegator.getAllocatedAt(slot, duration, timestamp),
                    delegator.getBalanceAt(slot.getParentIndex(), duration, timestamp)
                );
                assertLe(
                    delegator.getAllocatedAt(slot, duration, timestamp),
                    uint256(_slotSizeAt(delegator, slot, timestamp)) + pendingAt
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
        assertEq(parentSlot.firstChild, _slotFirstChildAt(delegator, parent, uint48(block.timestamp)));
        assertEq(parentSlot.lastChild, _slotLastChildAt(delegator, parent, uint48(block.timestamp)));
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
                _assertSharedParentPrefixState(delegator, child, childSlot, epochDuration, halfDuration, maxDuration);
            } else {
                _assertNonSharedParentPrefixState(
                    delegator,
                    child,
                    childSlot,
                    state.expectedPrevSize,
                    state.expectedPrevPending0,
                    state.expectedPrevPendingHalf,
                    state.expectedPrevPendingMax,
                    epochDuration,
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
        uint48 epochDuration,
        uint48 halfDuration,
        uint48 maxDuration
    ) internal view {
        assertEq(childSlot.prevSizeSum, 0);
        assertEq(_currentPrevPendingSum(delegator, child, 0, epochDuration), 0);
        assertEq(_currentPrevPendingSum(delegator, child, halfDuration, epochDuration), 0);
        assertEq(_currentPrevPendingSum(delegator, child, maxDuration, epochDuration), 0);
    }

    function _assertNonSharedParentPrefixState(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 child,
        IUniversalDelegator.Slot memory childSlot,
        uint208 expectedPrevSize,
        uint208 expectedPrevPending0,
        uint208 expectedPrevPendingHalf,
        uint208 expectedPrevPendingMax,
        uint48 epochDuration,
        uint48 halfDuration,
        uint48 maxDuration
    ) internal view {
        assertEq(childSlot.prevSizeSum, expectedPrevSize);
        assertEq(_currentPrevPendingSum(delegator, child, 0, epochDuration), expectedPrevPending0);
        assertEq(_currentPrevPendingSum(delegator, child, halfDuration, epochDuration), expectedPrevPendingHalf);
        assertEq(_currentPrevPendingSum(delegator, child, maxDuration, epochDuration), expectedPrevPendingMax);
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
        uint32 childIndex = _slotFirstChildAt(delegator, parent, timestamp);
        uint256 maxChildren = handler.getTrackedSlots().length + 1;

        for (uint256 visited; childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX; ++visited) {
            assertLt(visited, maxChildren);

            uint96 child = parent.createIndex(childIndex);
            total += delegator.getAllocatedAt(child, duration, timestamp);
            childIndex = _slotNextSlotAt(delegator, child, timestamp);
        }
    }

    function _slotStorageBase(uint96 index) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(index, uint256(SLOT_MAPPING_SLOT))));
    }

    function _slotTraceSlot(uint96 index, uint256 offset) internal pure returns (uint256) {
        return _slotStorageBase(index) + offset;
    }

    function _traceDataBase(uint256 traceSlot) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(traceSlot)));
    }

    function _traceLength(address target, uint256 traceSlot) internal view returns (uint256) {
        return uint256(vm.load(target, bytes32(traceSlot)));
    }

    function _traceAt(address target, uint256 traceSlot, uint256 pos)
        internal
        view
        returns (uint48 key, uint208 value)
    {
        uint256 raw = uint256(vm.load(target, bytes32(_traceDataBase(traceSlot) + pos)));
        key = uint48(raw);
        value = uint208(raw >> 48);
    }

    function _traceLatest(address target, uint256 traceSlot) internal view returns (uint208) {
        uint256 len = _traceLength(target, traceSlot);
        if (len == 0) {
            return 0;
        }

        (, uint208 value) = _traceAt(target, traceSlot, len - 1);
        return value;
    }

    function _traceLatestCheckpoint(address target, uint256 traceSlot)
        internal
        view
        returns (bool exists, uint48 key, uint208 value)
    {
        uint256 len = _traceLength(target, traceSlot);
        if (len == 0) {
            return (false, 0, 0);
        }

        (key, value) = _traceAt(target, traceSlot, len - 1);
        return (true, key, value);
    }

    function _traceUpperLookupRecent(address target, uint256 traceSlot, uint48 searchKey)
        internal
        view
        returns (uint208)
    {
        (, uint48 key, uint208 value) = _traceUpperLookupRecentCheckpoint(target, traceSlot, searchKey);
        return key <= searchKey ? value : 0;
    }

    function _traceUpperLookupRecentCheckpoint(address target, uint256 traceSlot, uint48 searchKey)
        internal
        view
        returns (bool exists, uint48 key, uint208 value)
    {
        uint256 len = _traceLength(target, traceSlot);
        if (len == 0) {
            return (false, 0, 0);
        }

        uint256 low;
        uint256 high = len;

        while (low < high) {
            uint256 mid = (low + high) / 2;
            (uint48 midKey,) = _traceAt(target, traceSlot, mid);
            if (midKey > searchKey) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        if (low == 0) {
            return (false, 0, 0);
        }

        (key, value) = _traceAt(target, traceSlot, low - 1);
        return (true, key, value);
    }

    function _slotPackedWord(UniversalDelegatorArithmeticHarness delegator, uint96 index)
        internal
        view
        returns (uint256)
    {
        return uint256(vm.load(address(delegator), bytes32(_slotStorageBase(index))));
    }

    function _slotChildrenPendingAt(UniversalDelegatorArithmeticHarness delegator, uint96 index)
        internal
        view
        returns (uint48)
    {
        return uint48(_slotPackedWord(delegator, index) >> (CHILDREN_PENDING_AT_OFFSET_BYTES * 8));
    }

    function _slotPendingCumulativeLatest(UniversalDelegatorArithmeticHarness delegator, uint96 index)
        internal
        view
        returns (uint208)
    {
        return _traceLatest(address(delegator), _slotTraceSlot(index, SLOT_TRACE_PENDING_CUMULATIVE_OFFSET));
    }

    function _slotPendingCumulativeAt(UniversalDelegatorArithmeticHarness delegator, uint96 index, uint48 timestamp)
        internal
        view
        returns (uint208)
    {
        return _traceUpperLookupRecent(
            address(delegator), _slotTraceSlot(index, SLOT_TRACE_PENDING_CUMULATIVE_OFFSET), timestamp
        );
    }

    function _slotClearedPendingCursorLatest(UniversalDelegatorArithmeticHarness delegator, uint96 index)
        internal
        view
        returns (uint208)
    {
        return _traceLatest(address(delegator), _slotTraceSlot(index, SLOT_TRACE_CLEARED_PENDING_CURSOR_OFFSET));
    }

    function _slotSharedSizeConsumedCumulativeLatest(UniversalDelegatorArithmeticHarness delegator, uint96 index)
        internal
        view
        returns (uint208)
    {
        return _traceLatest(address(delegator), _slotTraceSlot(index, SLOT_TRACE_SHARED_SIZE_CONSUMED_OFFSET));
    }

    function _slotSizeAt(UniversalDelegatorArithmeticHarness delegator, uint96 index, uint48 timestamp)
        internal
        view
        returns (uint208)
    {
        return _traceUpperLookupRecent(address(delegator), _slotTraceSlot(index, SLOT_TRACE_SIZE_OFFSET), timestamp);
    }

    function _slotFirstChildAt(UniversalDelegatorArithmeticHarness delegator, uint96 index, uint48 timestamp)
        internal
        view
        returns (uint32)
    {
        return uint32(
            _traceUpperLookupRecent(address(delegator), _slotTraceSlot(index, SLOT_TRACE_FIRST_CHILD_OFFSET), timestamp)
        );
    }

    function _slotLastChildAt(UniversalDelegatorArithmeticHarness delegator, uint96 index, uint48 timestamp)
        internal
        view
        returns (uint32)
    {
        return uint32(
            _traceUpperLookupRecent(address(delegator), _slotTraceSlot(index, SLOT_TRACE_LAST_CHILD_OFFSET), timestamp)
        );
    }

    function _slotNextSlotAt(UniversalDelegatorArithmeticHarness delegator, uint96 index, uint48 timestamp)
        internal
        view
        returns (uint32)
    {
        return uint32(
            _traceUpperLookupRecent(address(delegator), _slotTraceSlot(index, SLOT_TRACE_NEXT_SLOT_OFFSET), timestamp)
        );
    }

    function _noAdaptersPendingCumulativeLatest(UniversalDelegatorArithmeticHarness delegator)
        internal
        view
        returns (uint208)
    {
        return _traceLatest(address(delegator), NO_ADAPTERS_PENDING_CUMULATIVE_SLOT);
    }

    function _cursor(uint208 baseValue, uint208 cursorValue) internal pure returns (uint208) {
        return baseValue > cursorValue ? baseValue : cursorValue;
    }

    function _windowStart(uint48 timestamp, uint48 duration, uint48 epochDuration) internal pure returns (uint48) {
        uint256 delta = uint256(epochDuration) - uint256(duration);
        return timestamp > delta ? uint48(uint256(timestamp) - delta) : 0;
    }

    function _cursorForCurrentWindow(
        address target,
        uint256 baseTraceSlot,
        uint256 cursorTraceSlot,
        uint48 epochDuration
    ) internal view returns (uint208) {
        uint48 fromTimestamp = uint48(block.timestamp > epochDuration ? block.timestamp - epochDuration : 0);
        return
            _cursor(
                _traceUpperLookupRecent(target, baseTraceSlot, fromTimestamp), _traceLatest(target, cursorTraceSlot)
            );
    }

    function _pendingCursor(UniversalDelegatorArithmeticHarness delegator, uint96 index, uint48 epochDuration)
        internal
        view
        returns (uint208)
    {
        return _cursorForCurrentWindow(
            address(delegator),
            _slotTraceSlot(index, SLOT_TRACE_PENDING_CUMULATIVE_OFFSET),
            _slotTraceSlot(index, SLOT_TRACE_CLEARED_PENDING_CURSOR_OFFSET),
            epochDuration
        );
    }

    function _noAdaptersPendingCursor(UniversalDelegatorArithmeticHarness delegator, uint48 epochDuration)
        internal
        view
        returns (uint208)
    {
        return _cursorForCurrentWindow(
            address(delegator),
            NO_ADAPTERS_PENDING_CUMULATIVE_SLOT,
            CLEARED_NO_ADAPTERS_PENDING_CURSOR_SLOT,
            epochDuration
        );
    }

    function _sharedPendingCursor(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 networkIndex,
        uint48 epochDuration
    ) internal view returns (uint208) {
        uint96 parent = networkIndex.getParentIndex();
        return _cursorForCurrentWindow(
            address(delegator),
            _slotTraceSlot(parent, SLOT_TRACE_CLEARED_PENDING_CURSOR_OFFSET),
            _slotTraceSlot(networkIndex, SLOT_TRACE_SHARED_PENDING_CONSUMED_OFFSET),
            epochDuration
        );
    }

    function _sharedSizeCursor(UniversalDelegatorArithmeticHarness delegator, uint96 networkIndex, uint48 epochDuration)
        internal
        view
        returns (uint208)
    {
        uint96 parent = networkIndex.getParentIndex();
        return _cursorForCurrentWindow(
            address(delegator),
            _slotTraceSlot(parent, SLOT_TRACE_SHARED_SIZE_CONSUMED_OFFSET),
            _slotTraceSlot(networkIndex, SLOT_TRACE_SHARED_SIZE_CONSUMED_OFFSET),
            epochDuration
        );
    }

    function _currentPrevPendingSum(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 index,
        uint48 duration,
        uint48 epochDuration
    ) internal view returns (uint208 prevPendingSum) {
        if (index == 0) {
            return 0;
        }

        uint96 parent = index.getParentIndex();
        if (_isSharedParent(delegator, parent)) {
            return 0;
        }

        if (_slotChildrenPendingAt(delegator, parent) <= _windowStart(uint48(block.timestamp), duration, epochDuration))
        {
            return 0;
        }

        uint32 childIndex = delegator.getSlot(parent).firstChild;
        while (childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX) {
            uint96 child = parent.createIndex(childIndex);
            if (child == index) {
                break;
            }
            prevPendingSum += delegator.getPending(child, duration);
            childIndex = delegator.getSlot(child).nextSlot;
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

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
    uint256 internal constant SLOT_TRACE_SHARED_SIZE_CONSUMED_OFFSET = 7;

    struct CurrentParentState {
        uint208 expectedPrevSize;
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

    function invariant_CurrentSharedSizeCursorsNeverExceedCumulative() public view {
        UniversalDelegatorArithmeticHarness delegator = handler.delegator();
        uint48 epochDuration = handler.vault().epochDuration();
        uint96[] memory trackedSlots = handler.getTrackedSlots();

        for (uint256 i; i < trackedSlots.length; ++i) {
            uint96 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists) {
                continue;
            }

            if (slot.getDepth() == 2) {
                uint96 parent = slot.getParentIndex();
                if (delegator.getSlot(parent).exists && delegator.getSlot(parent).isShared) {
                    assertLe(
                        _sharedSizeCursor(delegator, slot, epochDuration),
                        _slotSharedSizeConsumedCumulativeLatest(delegator, parent)
                    );
                }
            }
        }
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

            expected += uint256(slot.size);
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
                _assertHistoricalAllocationBounds(delegator, slot, epochDuration, timestamp);
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

    function _assertHistoricalAllocationBounds(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 slot,
        uint48 epochDuration,
        uint48 timestamp
    ) internal view {
        for (uint256 i; i < 3; ++i) {
            uint48 duration = _durationAt(i, epochDuration);
            if (slot > 0) {
                assertLe(
                    delegator.getAllocatedAt(slot, duration, timestamp),
                    delegator.getBalanceAt(slot.getParentIndex(), duration, timestamp)
                );
                assertLe(
                    delegator.getAllocatedAt(slot, duration, timestamp),
                    uint256(_slotSizeAt(delegator, slot, timestamp))
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
                    state.expectedPrevSize
                );
            }

            state.expectedPrevSize += childSlot.latestSize;
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
    }

    function _assertNonSharedParentPrefixState(
        UniversalDelegatorArithmeticHarness delegator,
        uint96 child,
        IUniversalDelegator.Slot memory childSlot,
        uint208 expectedPrevSize
    ) internal view {
        assertEq(childSlot.prevSizeSum, expectedPrevSize);
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

    function _cursor(uint208 baseValue, uint208 cursorValue) internal pure returns (uint208) {
        return baseValue > cursorValue ? baseValue : cursorValue;
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

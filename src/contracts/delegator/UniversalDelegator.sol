// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";
import {VaultV2} from "../vault/VaultV2.sol";

import {Checkpoints} from "../libraries/CheckpointsV2.sol";
import {Subnetwork} from "../../contracts/libraries/Subnetwork.sol";
import {UniversalDelegatorIndex} from "../libraries/UniversalDelegatorIndex.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {
    IUniversalDelegator,
    MAX_SUBVAULTS,
    MAX_NETWORKS,
    MAX_OPERATORS,
    CREATE_SLOT_ROLE,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE,
    SET_WITHDRAWAL_BUFFER_SIZE_ROLE,
    WITHDRAWAL_BUFFER_INDEX,
    WITHDRAWAL_BUFFER_CHILD_INDEX
} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {
    OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE
} from "../../interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {VAULT_V2_VERSION} from "../../interfaces/vault/IVaultV2.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";

/// @title UniversalDelegator
/// @notice Contract for hierarchical stake allocation across subvaults, networks, and operators.
contract UniversalDelegator is
    Entity,
    StaticDelegateCallable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IUniversalDelegator
{
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;
    using UniversalDelegatorIndex for uint96;
    using Checkpoints for Checkpoints.Trace208;

    /* IMMUTABLES */

    /// @dev Address of the network registry.
    address internal immutable NETWORK_REGISTRY;
    /// @dev Address of the vault factory.
    address internal immutable VAULT_FACTORY;
    /// @dev Address of the network middleware service.
    address internal immutable NETWORK_MIDDLEWARE_SERVICE;

    /* STATE VARIABLES */

    struct SlotStorage {
        bool exists;
        bool isShared;
        bool noAdapters;
        uint32 prevSlot;
        uint32 totalChildren;
        uint32 existChildren;
        uint48 _childrenPendingAt;
        Checkpoints.Trace208 size;
        Checkpoints.Trace208 nextSlot;
        Checkpoints.Trace208 lastChild;
        Checkpoints.Trace208 firstChild;
        Checkpoints.Trace208 prevSizeSum;
        Checkpoints.Trace208 syncPrevSizeSums;
        Checkpoints.Trace208 pendingCumulative;
        Checkpoints.Trace208 clearedPendingCursor;
        Checkpoints.Trace208 sharedPendingConsumedCursor;
        Checkpoints.Trace208 sharedSizeConsumedCumulative;
    }

    /// @inheritdoc IUniversalDelegator
    address public vault;

    /// @dev Total slot size marked as no-adapters across root subvaults.
    uint256 internal _noAdaptersSize;
    /// @dev Slot storage keyed by encoded slot index.
    mapping(uint96 index => SlotStorage slot) internal slots;
    /// @dev Mapping from subnetwork id to slot index checkpoints.
    mapping(bytes32 subnetwork => Checkpoints.Trace208) internal _networkToSlot;
    /// @dev Mapping from slot index to subnetwork id.
    mapping(uint96 index => bytes32 subnetwork) internal _slotToNetwork;
    /// @dev Mapping from parent slot and operator to slot index checkpoints.
    mapping(uint96 parentIndex => mapping(address operator => Checkpoints.Trace208)) internal _operatorToSlot;
    /// @dev Mapping from slot index to operator address.
    mapping(uint96 index => address operator) internal _slotToOperator;
    /// @dev Cumulative pending no-adapters amounts.
    Checkpoints.Trace208 internal _noAdaptersPendingCumulative;
    /// @dev Cumulative cleared pending no-adapters amounts.
    Checkpoints.Trace208 internal _clearedNoAdaptersPendingCursor;
    /// @dev Maximum network limit per subnetwork.
    mapping(bytes32 subnetwork => Checkpoints.Trace208) internal _maxNetworkLimit;

    /// @inheritdoc IUniversalDelegator
    uint48 public migrateTimestamp;
    /// @inheritdoc IUniversalDelegator
    address public oldDelegator;

    /* MODIFIERS */

    modifier syncPrevSizeSums(uint96 parentIndex) {
        if (slots[parentIndex].syncPrevSizeSums.latest() > 0) {
            _syncPrevSizeSums(parentIndex);
            slots[parentIndex].syncPrevSizeSums.push(uint48(block.timestamp), 0);
        }
        _;
        _syncPrevSizeSums(parentIndex);
    }

    /// @dev Synchronize cumulative child size prefix sums for a parent slot.
    function _syncPrevSizeSums(uint96 parentIndex) internal {
        if (parentIndex.getDepth() == 1 && slots[parentIndex].isShared) {
            return;
        }
        uint32 childIndex = uint32(slots[parentIndex].firstChild.latest());
        if (childIndex == 0) {
            if (parentIndex == 0 && _withdrawalBufferSlot().prevSizeSum.latest() != 0) {
                _withdrawalBufferSlot().prevSizeSum.push(uint48(block.timestamp), 0);
            }
            return;
        }
        uint208 prevSum;
        for (; childIndex > 0;) {
            SlotStorage storage child = slots[parentIndex.createIndex(childIndex)];
            if (child.prevSizeSum.latest() != prevSum) {
                child.prevSizeSum.push(uint48(block.timestamp), prevSum);
            }
            prevSum += child.size.latest();
            childIndex = uint32(child.nextSlot.latest());
        }
    }

    /* MULTICALL */

    /// @inheritdoc IUniversalDelegator
    function multicall(bytes[] calldata data) public {
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /* CONSTRUCTOR */

    constructor(
        address networkRegistry,
        address vaultFactory,
        address delegatorFactory,
        uint64 entityType,
        address networkMiddlewareService
    ) Entity(delegatorFactory, entityType) {
        NETWORK_REGISTRY = networkRegistry;
        VAULT_FACTORY = vaultFactory;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
    }

    /// @inheritdoc IUniversalDelegator
    function VERSION() public pure returns (uint64) {
        return 2;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IUniversalDelegator
    function stakeForAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        public
        view
        returns (uint256)
    {
        return _maxNetworkLimit[subnetwork].upperLookupRecent(timestamp) > 0
            ? getAllocatedAt(subnetwork, operator, duration, timestamp)
            : 0;
    }

    /// @inheritdoc IUniversalDelegator
    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        return _maxNetworkLimit[subnetwork].latest() > 0 ? getAllocated(subnetwork, operator, duration) : 0;
    }

    /// @inheritdoc IUniversalDelegator
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes calldata)
        public
        view
        returns (uint256)
    {
        if (timestamp < migrateTimestamp) {
            // Legacy support.
            return IBaseDelegator(oldDelegator).stakeAt(subnetwork, operator, timestamp, "");
        }
        return getAllocatedAt(subnetwork, operator, _getEpochDuration() - 1, timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function stake(bytes32 subnetwork, address operator) public view returns (uint256) {
        return getAllocated(subnetwork, operator, _getEpochDuration() - 1);
    }

    /// @inheritdoc IUniversalDelegator
    function getSlot(uint96 index) public view returns (Slot memory) {
        return Slot({
            exists: slots[index].exists,
            nextSlot: uint32(slots[index].nextSlot.latest()),
            prevSlot: slots[index].prevSlot,
            totalChildren: slots[index].totalChildren,
            existChildren: slots[index].existChildren,
            firstChild: uint32(slots[index].firstChild.latest()),
            lastChild: uint32(slots[index].lastChild.latest()),
            isShared: slots[index].isShared,
            noAdapters: slots[index].noAdapters,
            size: uint128(slots[index].size.latest()),
            prevSizeSum: _getPrevSizeSum(index),
            subnetworkOrOperator: index.getDepth() == 3
                ? bytes20(_slotToOperator[index])
                : index.getDepth() == 2 ? _slotToNetwork[index] : bytes32(0)
        });
    }

    /// @inheritdoc IUniversalDelegator
    function getPendingAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint208) {
        return _getPendingAt(slots[index].pendingCumulative, slots[index].clearedPendingCursor, duration, timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function getPending(uint96 index, uint48 duration) public view returns (uint208) {
        return _getPending(slots[index].pendingCumulative, slots[index].clearedPendingCursor, duration);
    }

    /// @inheritdoc IUniversalDelegator
    function getBalanceAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        return index > 0
            ? getAllocatedAt(index, duration, timestamp)
            : VaultV2(vault).activeStakeAt(timestamp, "") + VaultV2(vault).activeWithdrawalsForAt(duration, timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function getBalance(uint96 index, uint48 duration) public view returns (uint256) {
        return index > 0
            ? getAllocated(index, duration)
            : VaultV2(vault).activeStake() + VaultV2(vault).activeWithdrawalsFor(duration);
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocatedAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        if (duration >= _getEpochDuration()) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        uint256 slotBalance = getBalanceAt(parentIndex, duration, timestamp);
        if (parentIndex.getDepth() != 1 || !slots[parentIndex].isShared) {
            slotBalance = slotBalance.saturatingSub(_getPrevSumAt(index, 0, timestamp));
        }
        return Math.min(slotBalance, _getPendingSizeAt(index, duration, timestamp));
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocated(uint96 index, uint48 duration) public view returns (uint256) {
        if (duration >= _getEpochDuration()) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        uint256 slotBalance = getBalance(parentIndex, duration);
        if (parentIndex.getDepth() == 1 && slots[parentIndex].isShared) {
            if (VaultV2(vault).slasher() == msg.sender) {
                // Support slashing without captureTimestamp for shared subvaults.
                slotBalance += _getSharedPendingGuarantee(index, duration) + _getSharedSizeGuarantee(index);
            }
        } else {
            slotBalance = slotBalance.saturatingSub(_getPrevSum(index, 0));
        }
        return Math.min(slotBalance, _getPendingSize(index, duration));
    }

    /// @inheritdoc IUniversalDelegator
    function getSlotOfNetworkAt(bytes32 subnetwork, uint48 timestamp) public view returns (uint96) {
        return uint96(_networkToSlot[subnetwork].upperLookupRecent(timestamp));
    }

    /// @inheritdoc IUniversalDelegator
    function getSlotOfNetwork(bytes32 subnetwork) public view returns (uint96) {
        return uint96(_networkToSlot[subnetwork].latest());
    }

    /// @inheritdoc IUniversalDelegator
    function getSlotOfOperatorAt(uint96 parentIndex, address operator, uint48 timestamp) public view returns (uint96) {
        return uint96(_operatorToSlot[parentIndex][operator].upperLookupRecent(timestamp));
    }

    /// @inheritdoc IUniversalDelegator
    function getSlotOfOperator(uint96 parentIndex, address operator) public view returns (uint96) {
        return uint96(_operatorToSlot[parentIndex][operator].latest());
    }

    /// @inheritdoc IUniversalDelegator
    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp) public view returns (uint96) {
        return getSlotOfOperatorAt(getSlotOfNetworkAt(subnetwork, timestamp), operator, timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function getSlotOf(bytes32 subnetwork, address operator) public view returns (uint96) {
        return getSlotOfOperator(getSlotOfNetwork(subnetwork), operator);
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        public
        view
        returns (uint256)
    {
        uint96 index = getSlotOfAt(subnetwork, operator, timestamp);
        return index > 0 ? getAllocatedAt(index, duration, timestamp) : 0;
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocated(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        uint96 index = getSlotOf(subnetwork, operator);
        return index > 0 ? getAllocated(index, duration) : 0;
    }

    /// @inheritdoc IUniversalDelegator
    function getFilledAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256 filled) {
        for (
            uint32 childIndex = uint32(slots[index].firstChild.upperLookupRecent(timestamp));
            childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX;

        ) {
            uint96 childSlotIndex = index.createIndex(childIndex);
            filled += getAllocatedAt(childSlotIndex, duration, timestamp);
            childIndex = uint32(slots[childSlotIndex].nextSlot.upperLookupRecent(timestamp));
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getFilled(uint96 index, uint48 duration) public view returns (uint256 filled) {
        for (
            uint32 childIndex = uint32(slots[index].firstChild.latest());
            childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX;

        ) {
            uint96 childSlotIndex = index.createIndex(childIndex);
            filled += getAllocated(childSlotIndex, duration);
            childIndex = uint32(slots[childSlotIndex].nextSlot.latest());
        }
    }

    /// @inheritdoc IUniversalDelegator
    function maxNetworkLimit(bytes32 subnetwork) public view returns (uint256) {
        if (_maxNetworkLimit[subnetwork].length() == 0 && migrateTimestamp > 0) {
            // Legacy support.
            return IBaseDelegator(oldDelegator).maxNetworkLimit(subnetwork) > 0 ? type(uint208).max : 0;
        }
        return _maxNetworkLimit[subnetwork].latest();
    }

    /// @inheritdoc IUniversalDelegator
    function getIsShared(bytes32 subnetwork) public view returns (bool) {
        uint96 index = getSlotOfNetwork(subnetwork);
        if (index == 0) {
            revert NotAssigned();
        }
        return slots[index.getParentIndex()].isShared;
    }

    /// @inheritdoc IUniversalDelegator
    function getIsNoAdapters(bytes32 subnetwork) public view returns (bool) {
        uint96 index = getSlotOfNetwork(subnetwork);
        if (index == 0) {
            revert NotAssigned();
        }
        return slots[index.getParentIndex()].noAdapters;
    }

    /// @inheritdoc IUniversalDelegator
    function getNoAdaptersSize() public view returns (uint256) {
        return _noAdaptersSize + _getPending(_noAdaptersPendingCumulative, _clearedNoAdaptersPendingCursor, 0);
    }

    /// @inheritdoc IUniversalDelegator
    function getWithdrawalBuffer() public view returns (uint256) {
        return getAllocated(WITHDRAWAL_BUFFER_INDEX, 0);
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IUniversalDelegator
    function createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noAdapters, uint128 size)
        public
        onlyRole(CREATE_SLOT_ROLE)
        returns (uint96 index)
    {
        return _createSlot(subnetworkOrOperator, parentIndex, isShared, noAdapters, size);
    }

    /// @dev Create a new slot.
    function _createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noAdapters, uint128 size)
        internal
        syncPrevSizeSums(parentIndex)
        returns (uint96 index)
    {
        _revertIfNotExists(parentIndex);
        if (parentIndex.getDepth() > 0 && (isShared || noAdapters)) {
            revert WrongDepth();
        }

        SlotStorage storage parent = slots[parentIndex];
        if (
            ++parent.existChildren
                > (parentIndex.getDepth() == 0
                        ? MAX_SUBVAULTS
                        : parentIndex.getDepth() == 1 ? MAX_NETWORKS : MAX_OPERATORS)
        ) {
            revert TooManyChildren();
        }
        ++parent.totalChildren;

        index = parentIndex.createIndex(parent.totalChildren);

        if (parentIndex.getDepth() == 1) {
            if (_networkToSlot[subnetworkOrOperator].latest() > 0) {
                revert AlreadyAssigned();
            }
            _networkToSlot[subnetworkOrOperator].push(uint48(block.timestamp), index);
            _slotToNetwork[index] = subnetworkOrOperator;

            // Legacy support.
            if (_maxNetworkLimit[subnetworkOrOperator].length() == 0 && migrateTimestamp > 0) {
                _maxNetworkLimit[subnetworkOrOperator].push(
                    uint48(block.timestamp),
                    maxNetworkLimit(subnetworkOrOperator) > 0 && parentIndex.getChildIndex() == 1
                        ? type(uint208).max
                        : 0
                );
            }
        } else if (parentIndex.getDepth() == 2) {
            if (_operatorToSlot[parentIndex][address(bytes20(subnetworkOrOperator))].latest() > 0) {
                revert AlreadyAssigned();
            }
            _operatorToSlot[parentIndex][address(bytes20(subnetworkOrOperator))].push(uint48(block.timestamp), index);
            _slotToOperator[index] = address(bytes20(subnetworkOrOperator));
        }

        SlotStorage storage slot = slots[index];

        slot.exists = true;
        if (parent.firstChild.latest() == 0) {
            parent.firstChild.push(uint48(block.timestamp), index.getChildIndex());
        } else {
            uint96 lastIndex = parentIndex.createIndex(uint32(parent.lastChild.latest()));
            slots[lastIndex].nextSlot.push(uint48(block.timestamp), index.getChildIndex());
            slot.prevSlot = uint32(parent.lastChild.latest());
        }
        parent.lastChild.push(uint48(block.timestamp), index.getChildIndex());
        if (size > 0) {
            slot.size.push(uint48(block.timestamp), size);
        }

        if (parentIndex.getDepth() == 0) {
            slots[index].nextSlot.push(uint48(block.timestamp), WITHDRAWAL_BUFFER_CHILD_INDEX);
            slot.isShared = isShared;
            if (noAdapters) {
                if (size > VaultV2(vault).allocatable()) {
                    revert NotEnoughNoAdapters();
                }
                slot.noAdapters = true;
                _noAdaptersSize += size;
            }
        } else if (parentIndex.getDepth() == 1 && parent.isShared) {
            slot.sharedPendingConsumedCursor.push(uint48(block.timestamp), parent.clearedPendingCursor.latest());
            slot.sharedSizeConsumedCumulative
                .push(uint48(block.timestamp), parent.sharedSizeConsumedCumulative.latest());
        }

        emit CreateSlot(index, isShared, noAdapters, size);
    }

    /// @inheritdoc IUniversalDelegator
    function setSize(uint96 index, uint128 newSize)
        public
        onlyRole(SET_SIZE_ROLE)
        syncPrevSizeSums(index.getParentIndex())
    {
        _revertIfNotExists(index);
        SlotStorage storage slot = slots[index];
        uint128 curSize = uint128(slot.size.latest());
        if (curSize == newSize) {
            return;
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];

        if (newSize > curSize) {
            uint48 maxDuration = _getEpochDuration() - 1;
            uint256 curBalance = getBalance(parentIndex, 0);
            uint256 minBalance = getBalance(parentIndex, maxDuration);
            if (
                !parent.isShared && _getPrevSum(index, maxDuration) + curSize < curBalance && slot.nextSlot.latest() > 0
                    && slot.nextSlot.latest() < WITHDRAWAL_BUFFER_CHILD_INDEX
            ) {
                uint96 lastIndex = parentIndex.createIndex(uint32(parent.lastChild.latest()));
                if (
                    newSize - curSize
                        > minBalance.saturatingSub(
                            _getPrevSum(lastIndex, 0) + slots[lastIndex].size.latest() + getPending(lastIndex, 0)
                        )
                ) {
                    revert NotEnoughBalance();
                }
            }
            if (slot.noAdapters && newSize - curSize > VaultV2(vault).allocatable()) {
                revert NotEnoughNoAdapters();
            }
        } else {
            uint208 addPending = uint208(getAllocated(index, 0).saturatingSub(getPending(index, 0) + newSize));
            if (addPending > 0) {
                parent._childrenPendingAt = uint48(block.timestamp);
                slot.pendingCumulative.push(uint48(block.timestamp), slot.pendingCumulative.latest() + addPending);
                if (slot.noAdapters) {
                    _noAdaptersPendingCumulative.push(
                        uint48(block.timestamp), _noAdaptersPendingCumulative.latest() + addPending
                    );
                }
            }
        }
        slot.size.push(uint48(block.timestamp), newSize);
        if (slot.noAdapters) {
            _noAdaptersSize = _noAdaptersSize - curSize + newSize;
        }

        emit SetSize(index, newSize);
    }

    /// @inheritdoc IUniversalDelegator
    function swapSlots(uint96 index1, uint96 index2)
        public
        onlyRole(SWAP_SLOTS_ROLE)
        syncPrevSizeSums(index1.getParentIndex())
    {
        _revertIfNotExists(index1);
        _revertIfNotExists(index2);
        uint96 parentIndex = index1.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];

        if (parentIndex != index2.getParentIndex()) {
            revert NotSameParent();
        }
        if (parent.isShared) {
            revert IsShared();
        }
        for (
            uint32 childIndex = index2.getChildIndex();
            childIndex > 0;
            childIndex = uint32(slots[parentIndex.createIndex(childIndex)].nextSlot.latest())
        ) {
            if (childIndex == index1.getChildIndex()) {
                revert WrongOrder();
            }
        }
        {
            uint48 maxDuration = _getEpochDuration() - 1;
            uint256 minBalance = getBalance(parentIndex, maxDuration);
            uint256 curPrevSum = _getPrevSum(index2, 0);

            // - slot2 fully allocated at maxDuration (epochDuration - 1) => slot1 is fully allocated too,
            // - slot1 unallocated at duration=0 => slot2 is unallocated too,
            // - otherwise, revert.
            if (curPrevSum < minBalance) {
                if (curPrevSum + slots[index2].size.latest() + getPending(index2, 0) > minBalance) {
                    revert PartiallyAllocated();
                }
            } else if (_getPrevSum(index1, maxDuration) < getBalance(parentIndex, 0)) {
                revert NotSameAllocated();
            }
        }

        if (index1.getChildIndex() == parent.firstChild.latest()) {
            parent.firstChild.push(uint48(block.timestamp), index2.getChildIndex());
        }
        if (index2.getChildIndex() == parent.lastChild.latest()) {
            parent.lastChild.push(uint48(block.timestamp), index1.getChildIndex());
        }

        SlotStorage storage slot1 = slots[index1];
        SlotStorage storage slot2 = slots[index2];

        uint32 nextSlot1 = uint32(slot1.nextSlot.latest());
        slot1.nextSlot.push(uint48(block.timestamp), uint32(slot2.nextSlot.latest()));
        slot2.nextSlot.push(uint48(block.timestamp), nextSlot1);

        if (slot1.nextSlot.latest() > 0) {
            slots[parentIndex.createIndex(uint32(slot1.nextSlot.latest()))].prevSlot = index1.getChildIndex();
        }
        slots[parentIndex.createIndex(uint32(slot2.nextSlot.latest()))].prevSlot = index2.getChildIndex();

        (slot1.prevSlot, slot2.prevSlot) = (slot2.prevSlot, slot1.prevSlot);

        slots[parentIndex.createIndex(slot1.prevSlot)].nextSlot.push(uint48(block.timestamp), index1.getChildIndex());
        if (slot2.prevSlot > 0) {
            slots[parentIndex.createIndex(uint32(slot2.prevSlot))].nextSlot
                .push(uint48(block.timestamp), index2.getChildIndex());
        }

        emit SwapSlots(index1, index2);
    }

    /// @inheritdoc IUniversalDelegator
    function removeSlot(uint96 index) public onlyRole(REMOVE_SLOT_ROLE) syncPrevSizeSums(index.getParentIndex()) {
        _revertIfNotExists(index);
        if (getAllocated(index, 0) > 0) {
            revert SlotAllocated();
        }

        _removeSlot(index);
        emit RemoveSlot(index);
    }

    /// @dev Remove a slot from the linked-list structure and mark it as non-existent.
    function _removeSlot(uint96 index) internal {
        SlotStorage storage slot = slots[index];
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];

        if (index.getDepth() == 1) {
            for (
                uint32 childIndex = uint32(slot.firstChild.latest());
                childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX;

            ) {
                uint96 curIndex = index.createIndex(childIndex);
                bytes32 subnetwork = _slotToNetwork[curIndex];
                _networkToSlot[subnetwork].push(uint48(block.timestamp), 0);
                _slotToNetwork[curIndex] = bytes32(0);
                if (_maxNetworkLimit[subnetwork].latest() > 0) {
                    _maxNetworkLimit[subnetwork].push(uint48(block.timestamp), 0);
                }
                childIndex = uint32(slots[curIndex].nextSlot.latest());
            }
        } else if (index.getDepth() == 2) {
            bytes32 subnetwork = _slotToNetwork[index];
            _networkToSlot[subnetwork].push(uint48(block.timestamp), 0);
            _slotToNetwork[index] = bytes32(0);
            if (_maxNetworkLimit[subnetwork].latest() > 0) {
                _maxNetworkLimit[subnetwork].push(uint48(block.timestamp), 0);
            }
        } else if (index.getDepth() == 3) {
            _operatorToSlot[parentIndex][_slotToOperator[index]].push(uint48(block.timestamp), 0);
            _slotToOperator[index] = address(0);
        }

        if (index.getChildIndex() == parent.firstChild.latest()) {
            uint32 nextChildIndex = uint32(slot.nextSlot.latest());
            parent.firstChild
                .push(
                    uint48(block.timestamp),
                    index.getDepth() > 1 || nextChildIndex < WITHDRAWAL_BUFFER_CHILD_INDEX ? nextChildIndex : 0
                );
        } else {
            slots[parentIndex.createIndex(slot.prevSlot)].nextSlot
                .push(uint48(block.timestamp), uint32(slot.nextSlot.latest()));
        }
        if (index.getChildIndex() == parent.lastChild.latest()) {
            parent.lastChild.push(uint48(block.timestamp), slot.prevSlot);
        } else {
            slots[parentIndex.createIndex(uint32(slot.nextSlot.latest()))].prevSlot = slot.prevSlot;
        }

        if (index.getDepth() == 1 && slot.noAdapters) {
            uint208 pending = getPending(index, 0);
            if (pending > 0) {
                _clearedNoAdaptersPendingCursor.push(uint48(block.timestamp), _getNoAdaptersPendingCursor() + pending);
            }

            _noAdaptersSize -= slot.size.latest();
        }

        --parent.existChildren;
        slot.exists = false;
    }

    /// @inheritdoc IUniversalDelegator
    function setWithdrawalBufferSize(uint128 newWithdrawalBufferSize) public onlyRole(SET_WITHDRAWAL_BUFFER_SIZE_ROLE) {
        _withdrawalBufferSlot().size.push(uint48(block.timestamp), newWithdrawalBufferSize);

        emit SetWithdrawalBufferSize(newWithdrawalBufferSize);
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

    /// @inheritdoc IUniversalDelegator
    function setMaxNetworkLimit(uint96 identifier, uint256 amount) public {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }
        bytes32 subnetwork = (msg.sender).subnetwork(identifier);
        if (maxNetworkLimit(subnetwork) > 0) {
            revert AlreadySet();
        }
        if (amount < type(uint256).max) {
            revert LimitNotUint256Max();
        }
        _maxNetworkLimit[subnetwork].push(uint48(block.timestamp), type(uint208).max);

        emit SetMaxNetworkLimit(subnetwork, amount);
    }

    /// @inheritdoc IUniversalDelegator
    function resetAllocation(bytes32 subnetwork) public {
        if (
            !IRegistry(NETWORK_REGISTRY).isEntity(subnetwork.network())
                || (subnetwork.network() != msg.sender
                    && INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network())
                        != msg.sender)
        ) {
            revert NotNetworkOrMiddleware();
        }

        uint96 index = getSlotOfNetwork(subnetwork);
        if (index == 0) {
            revert NotAssigned();
        }
        if (slots[index.getParentIndex()].existChildren == 1) {
            index = index.getParentIndex();
        }
        SlotStorage storage slot = slots[index];
        SlotStorage storage parent = slots[index.getParentIndex()];

        if (
            slot.size.latest() > 0 && parent.syncPrevSizeSums.latest() == 0
                && (index.getDepth() == 1 || (!parent.isShared && slot.nextSlot.latest() > 0))
        ) {
            parent.syncPrevSizeSums.push(uint48(block.timestamp), 1);
        }

        // Remove slot to restrict from slashing.
        _removeSlot(index);

        emit ResetAllocation(index, subnetwork);
    }

    /* PUBLIC FUNCTIONS (INTERNAL LOGIC) */

    /// @dev Apply slash accounting updates across the affected slot chain.
    function onSlash(bytes32 subnetwork, address operator, uint256 amount)
        public
        nonReentrant
        returns (uint256 actualAmount)
    {
        if (VaultV2(vault).slasher() != msg.sender) {
            revert NotSlasher();
        }

        actualAmount = amount;
        uint96 index = getSlotOf(subnetwork, operator);
        uint96 networkIndex = index.getParentIndex();

        // Adjust slot's and its parents' allocations.
        for (uint96 curIndex = index; curIndex > 0;) {
            SlotStorage storage slot = slots[curIndex];
            SlotStorage storage parent = slots[curIndex.getParentIndex()];
            uint208 pendingSlashed = uint208(Math.min(getPending(curIndex, 0), amount));
            uint128 sizeSlashed = uint128(Math.min(slot.size.latest(), amount - pendingSlashed));
            actualAmount = Math.min(actualAmount, pendingSlashed + sizeSlashed);
            if (curIndex.getDepth() == 1 && slot.isShared) {
                // Actual slashed amount can be lower than requested due to slashing by multiple shared networks.
                actualAmount = Math.min(actualAmount, getAllocated(curIndex, 0));
            }
            if (pendingSlashed > 0) {
                // Clear slot's pending.
                slot.clearedPendingCursor.push(uint48(block.timestamp), _getPendingCursor(curIndex) + pendingSlashed);

                // Clear no-adapters pending.
                if (curIndex.getDepth() == 1 && slot.noAdapters) {
                    _clearedNoAdaptersPendingCursor.push(
                        uint48(block.timestamp), _getNoAdaptersPendingCursor() + pendingSlashed
                    );
                }
            }
            if (sizeSlashed > 0) {
                // Clear slot's size.
                slot.size.push(uint48(block.timestamp), slot.size.latest() - sizeSlashed);
                if (
                    parent.syncPrevSizeSums.latest() == 0
                        && (curIndex.getDepth() == 1
                            || ((curIndex.getDepth() == 3 || !parent.isShared) && slot.nextSlot.latest() > 0))
                ) {
                    parent.syncPrevSizeSums.push(uint48(block.timestamp), 1);
                }
                if (curIndex.getDepth() == 1 && slot.noAdapters) {
                    // Clear no-adapters size.
                    _noAdaptersSize -= sizeSlashed;
                }
            }
            if (curIndex.getDepth() == 1 && slot.isShared) {
                // Consume guarantees for shared subvault.
                if (sizeSlashed > 0) {
                    slot.sharedSizeConsumedCumulative
                        .push(uint48(block.timestamp), slot.sharedSizeConsumedCumulative.latest() + sizeSlashed);
                }
                uint208 pendingConsumed = uint208(Math.min(_getSharedPendingGuarantee(networkIndex, 0), amount));
                if (pendingConsumed > 0) {
                    slots[networkIndex].sharedPendingConsumedCursor
                        .push(uint48(block.timestamp), _getSharedPendingCursor(networkIndex) + pendingConsumed);
                }
                uint208 sizeConsumed =
                    uint208(Math.min(_getSharedSizeGuarantee(networkIndex), amount - pendingConsumed));
                if (sizeConsumed > 0) {
                    slots[networkIndex].sharedSizeConsumedCumulative
                        .push(uint48(block.timestamp), _getSharedSizeCursor(networkIndex) + sizeConsumed);
                }
            }
            curIndex = curIndex.getParentIndex();
        }

        emit OnSlash(subnetwork, operator, amount);
    }

    /* INITIALIZATION */

    /// @dev Initialize delegator state from encoded initialization parameters.
    function _initialize(bytes calldata data) internal override {
        (address initVault, bytes memory initData) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(initVault)) {
            revert NotVault();
        }
        if (IMigratableEntity(initVault).version() < VAULT_V2_VERSION) {
            revert OldVault();
        }

        InitParams memory params = abi.decode(initData, (InitParams));

        __ReentrancyGuard_init();

        vault = initVault;

        _withdrawalBufferSlot().size.push(uint48(block.timestamp), params.withdrawalBufferSize);

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(CREATE_SLOT_ROLE, params.createSlotRoleHolder);
        _grantRoleIfNotZero(SET_SIZE_ROLE, params.setSizeRoleHolder);
        _grantRoleIfNotZero(SWAP_SLOTS_ROLE, params.swapSlotsRoleHolder);
        _grantRoleIfNotZero(REMOVE_SLOT_ROLE, params.removeSlotRoleHolder);
        _grantRoleIfNotZero(SET_WITHDRAWAL_BUFFER_SIZE_ROLE, params.setWithdrawalBufferSizeRoleHolder);

        emit Initialize(params);
    }

    /* MIGRATION */

    /// @dev Migrate delegator state from the previously configured delegator.
    function migrate(address oldDelegator_) public {
        if (vault != msg.sender) {
            revert NotVault();
        }
        migrateTimestamp = uint48(block.timestamp);
        oldDelegator = oldDelegator_;

        _createSlot(
            bytes32(0),
            0,
            IEntity(oldDelegator_).TYPE() < OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE,
            true,
            uint128(Math.min(VaultV2(vault).allocatable(), type(uint128).max))
        );
    }

    /* UTILITY FUNCTIONS */

    /// @dev Get the pending size at a specific timestamp.
    function _getPendingSizeAt(uint96 index, uint48 duration, uint48 timestamp) internal view returns (uint208) {
        return slots[index].size.upperLookupRecent(timestamp) + getPendingAt(index, duration, timestamp);
    }

    /// @dev Get the current slot size plus pending stake within the requested duration window.
    function _getPendingSize(uint96 index, uint48 duration) internal view returns (uint208) {
        return slots[index].size.latest() + getPending(index, duration);
    }

    /// @dev Get the prefix sum of previous sibling sizes at a timestamp.
    function _getPrevSizeSumAt(uint96 index, uint48 timestamp) internal view returns (uint208 prevSizeSum) {
        if (index == 0) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        if (parentIndex.getDepth() == 1 && parent.isShared) {
            return 0;
        }
        if (parent.syncPrevSizeSums.upperLookupRecent(timestamp) == 0) {
            return slots[index].prevSizeSum.upperLookupRecent(timestamp);
        }
        for (uint32 childIndex = uint32(parent.firstChild.upperLookupRecent(timestamp)); childIndex > 0;) {
            uint96 curIndex = parentIndex.createIndex(childIndex);
            if (index == curIndex) {
                break;
            }
            prevSizeSum += slots[curIndex].size.upperLookupRecent(timestamp);
            childIndex = uint32(slots[curIndex].nextSlot.upperLookupRecent(timestamp));
        }
    }

    /// @dev Get the current prefix sum of previous sibling sizes.
    function _getPrevSizeSum(uint96 index) internal view returns (uint208 prevSizeSum) {
        if (index == 0) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        if (parentIndex.getDepth() == 1 && parent.isShared) {
            return 0;
        }
        if (parent.syncPrevSizeSums.latest() == 0) {
            return slots[index].prevSizeSum.latest();
        }
        for (uint32 childIndex = uint32(parent.firstChild.latest()); childIndex > 0;) {
            uint96 curIndex = parentIndex.createIndex(childIndex);
            if (index == curIndex) {
                break;
            }
            prevSizeSum += slots[curIndex].size.latest();
            childIndex = uint32(slots[curIndex].nextSlot.latest());
        }
    }

    /// @dev Get the prefix sum of previous sibling pending amounts within the duration window at a timestamp.
    function _getPrevPendingSumAt(uint96 index, uint48 duration, uint48 timestamp)
        internal
        view
        returns (uint208 prevPendingSum)
    {
        if (index == 0) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        if (parentIndex.getDepth() == 1 && parent.isShared) {
            return 0;
        }
        for (uint32 childIndex = uint32(parent.firstChild.upperLookupRecent(timestamp)); childIndex > 0;) {
            uint96 curIndex = parentIndex.createIndex(childIndex);
            if (index == curIndex) {
                break;
            }
            prevPendingSum += getPendingAt(curIndex, duration, timestamp);
            childIndex = uint32(slots[curIndex].nextSlot.upperLookupRecent(timestamp));
        }
    }

    /// @dev Get the current prefix sum of previous sibling pending amounts within the duration window.
    function _getPrevPendingSum(uint96 index, uint48 duration) internal view returns (uint208 prevPendingSum) {
        if (index == 0) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        if (parentIndex.getDepth() == 1 && parent.isShared) {
            return 0;
        }
        if (
            parent._childrenPendingAt
                <= block.timestamp.saturatingSub(uint256(_getEpochDuration()).saturatingSub(duration))
        ) {
            return 0;
        }
        for (uint32 childIndex = uint32(parent.firstChild.latest()); childIndex > 0;) {
            uint96 curIndex = parentIndex.createIndex(childIndex);
            if (index == curIndex) {
                break;
            }
            prevPendingSum += getPending(curIndex, duration);
            childIndex = uint32(slots[curIndex].nextSlot.latest());
        }
    }

    /// @dev Get the total size-plus-pending prefix sum of previous siblings at a timestamp.
    function _getPrevSumAt(uint96 index, uint48 duration, uint48 timestamp) internal view returns (uint208) {
        return _getPrevSizeSumAt(index, timestamp) + _getPrevPendingSumAt(index, duration, timestamp);
    }

    /// @dev Get the current total size-plus-pending prefix sum of previous siblings.
    function _getPrevSum(uint96 index, uint48 duration) internal view returns (uint208) {
        return _getPrevSizeSum(index) + _getPrevPendingSum(index, duration);
    }

    /// @dev Get the effective cleared-pending cursor for a slot in the current window.
    function _getPendingCursor(uint96 index) internal view returns (uint208) {
        return _getCursor(slots[index].pendingCumulative, slots[index].clearedPendingCursor);
    }

    /// @dev Get the effective cleared-pending cursor for the global no-adapters lane.
    function _getNoAdaptersPendingCursor() internal view returns (uint208) {
        return _getCursor(_noAdaptersPendingCumulative, _clearedNoAdaptersPendingCursor);
    }

    /// @dev Get the effective shared-size consumption cursor for a network under a shared subvault.
    function _getSharedSizeCursor(uint96 networkIndex) internal view returns (uint208) {
        return _getCursor(
            slots[networkIndex.getParentIndex()].sharedSizeConsumedCumulative,
            slots[networkIndex].sharedSizeConsumedCumulative
        );
    }

    /// @dev Get the remaining shared size guarantee available to a network.
    function _getSharedSizeGuarantee(uint96 networkIndex) internal view returns (uint208) {
        return uint208(
            uint256(slots[networkIndex.getParentIndex()].sharedSizeConsumedCumulative.latest())
                .saturatingSub(_getSharedSizeCursor(networkIndex))
        );
    }

    /// @dev Get the effective shared pending cursor for a network under a shared subvault.
    function _getSharedPendingCursor(uint96 networkIndex) internal view returns (uint208) {
        return _getCursor(
            slots[networkIndex.getParentIndex()].clearedPendingCursor, slots[networkIndex].sharedPendingConsumedCursor
        );
    }

    /// @dev Get the remaining shared pending guarantee available to a network for the duration window.
    function _getSharedPendingGuarantee(uint96 networkIndex, uint48 duration) internal view returns (uint208) {
        return _getPending(
            slots[networkIndex.getParentIndex()].clearedPendingCursor,
            slots[networkIndex].sharedPendingConsumedCursor,
            duration
        );
    }

    /// @dev Get the effective cursor after applying the rolling epoch floor to a cumulative series.
    function _getCursor(Checkpoints.Trace208 storage base, Checkpoints.Trace208 storage cursor)
        internal
        view
        returns (uint208)
    {
        return uint208(
            Math.max(
                base.upperLookupRecent(uint48(block.timestamp.saturatingSub(_getEpochDuration()))), cursor.latest()
            )
        );
    }

    /// @dev Get a pending amount in a duration window at a specific timestamp.
    function _getPendingAt(
        Checkpoints.Trace208 storage base,
        Checkpoints.Trace208 storage cursor,
        uint48 duration,
        uint48 timestamp
    ) internal view returns (uint208) {
        if (base.length() == 0) {
            return 0;
        }
        uint48 fromTimestamp =
            uint48(uint256(timestamp).saturatingSub(uint256(_getEpochDuration()).saturatingSub(duration)));
        (, uint48 lastPendingKey, uint208 pendingCumulativeLatest,) = base.upperLookupRecentCheckpoint(timestamp);
        if (lastPendingKey <= fromTimestamp) {
            return 0;
        }
        return pendingCumulativeLatest
            - uint208(Math.max(base.upperLookupRecent(fromTimestamp), cursor.upperLookupRecent(timestamp)));
    }

    /// @dev Get the current pending amount in a duration window.
    function _getPending(Checkpoints.Trace208 storage base, Checkpoints.Trace208 storage cursor, uint48 duration)
        internal
        view
        returns (uint208)
    {
        if (base.length() == 0) {
            return 0;
        }
        uint48 fromTimestamp =
            uint48(block.timestamp.saturatingSub(uint256(_getEpochDuration()).saturatingSub(duration)));
        (, uint48 lastPendingKey, uint208 pendingCumulativeLatest) = base.latestCheckpoint();
        if (lastPendingKey <= fromTimestamp) {
            return 0;
        }
        return pendingCumulativeLatest - uint208(Math.max(base.upperLookupRecent(fromTimestamp), cursor.latest()));
    }

    /// @dev Read the connected vault epoch duration.
    function _getEpochDuration() internal view returns (uint48) {
        return VaultV2(vault).epochDuration();
    }

    /// @dev Get the storage pointer to the withdrawal buffer slot.
    function _withdrawalBufferSlot() internal view returns (SlotStorage storage) {
        return slots[WITHDRAWAL_BUFFER_INDEX];
    }

    /// @dev Revert when a non-zero slot index does not exist.
    function _revertIfNotExists(uint96 index) internal view {
        if (index > 0 && !slots[index].exists) {
            revert SlotNotExists();
        }
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}

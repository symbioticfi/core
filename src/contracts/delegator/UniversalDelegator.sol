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
import {IDelegatorHook} from "../../interfaces/delegator/IDelegatorHookV2.sol";
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
    HOOK_GAS_LIMIT,
    HOOK_RESERVE,
    HOOK_SET_ROLE,
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
        bool noPlugins;
        uint32 prevSlot;
        uint32 totalChildren;
        uint32 existChildren;
        uint48 _childrenPendingAt;
        Checkpoints.Trace208 size;
        Checkpoints.Trace208 prevSizeSum;
        Checkpoints.Trace208 syncPrevSizeSums;
        Checkpoints.Trace208 nextSlot;
        Checkpoints.Trace208 lastChild;
        Checkpoints.Trace208 firstChild;
        Checkpoints.Trace208 pendingCumulative;
        Checkpoints.Trace208 clearedPendingCursor;
    }

    /// @inheritdoc IUniversalDelegator
    address public vault;
    /// @inheritdoc IUniversalDelegator
    address public hook;

    /// @dev Total slot size marked as no-plugins across root subvaults.
    uint256 internal _noPluginsSize;
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
    /// @dev Cumulative pending no-plugins amounts.
    Checkpoints.Trace208 internal _noPluginsPendingCumulative;
    /// @dev Cumulative cleared pending no-plugins amounts.
    Checkpoints.Trace208 internal _clearedNoPluginsPendingCursor;
    /// @dev Maximum network limit per subnetwork.
    mapping(bytes32 subnetwork => Checkpoints.Trace208) internal _maxNetworkLimit;

    /// @dev Timestamp when migration from the previous delegator occurred.
    uint48 internal __migrateTimestamp;
    /// @dev Address of the previous delegator during migration.
    address internal __oldDelegator;

    /* MODIFIERS */

    modifier slotExists(uint96 index) {
        if (index > 0 && !slots[index].exists) {
            revert SlotNotCreated();
        }
        _;
    }

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
        unchecked {
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
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        public
        view
        returns (uint256)
    {
        if (timestamp < __migrateTimestamp) {
            // Legacy support.
            return IBaseDelegator(__oldDelegator).stakeAt(subnetwork, operator, timestamp, hints);
        }
        return getAllocatedAt(subnetwork, operator, VaultV2(vault).epochDuration() - 1, timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function stake(bytes32 subnetwork, address operator) public view returns (uint256) {
        return getAllocated(subnetwork, operator, VaultV2(vault).epochDuration() - 1);
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
            noPlugins: slots[index].noPlugins,
            size: uint128(slots[index].size.latest()),
            prevSizeSum: _getPrevSizeSum(index),
            subnetworkOrOperator: index.getDepth() == 3
                ? bytes20(_slotToOperator[index])
                : index.getDepth() == 2 ? _slotToNetwork[index] : bytes32(0)
        });
    }

    /// @inheritdoc IUniversalDelegator
    function getPendingAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint208) {
        unchecked {
            SlotStorage storage slot = slots[index];
            if (slot.pendingCumulative.length() == 0) {
                return 0;
            }

            uint48 fromTimestamp = uint48(
                uint256(timestamp).saturatingSub(uint256(VaultV2(vault).epochDuration()).saturatingSub(duration))
            );
            (, uint48 lastPendingAtKey, uint208 pendingCumulativeAt,) =
                slot.pendingCumulative.upperLookupRecentCheckpoint(timestamp);
            if (lastPendingAtKey <= fromTimestamp) {
                return 0;
            }

            return pendingCumulativeAt
                - uint208(
                Math.max(
                slot.clearedPendingCursor.upperLookupRecent(timestamp),
                slot.pendingCumulative.upperLookupRecent(fromTimestamp)
            )
            );
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getPending(uint96 index, uint48 duration) public view returns (uint208) {
        unchecked {
            SlotStorage storage slot = slots[index];
            if (slot.pendingCumulative.length() == 0) {
                return 0;
            }

            uint48 fromTimestamp =
                uint48(block.timestamp.saturatingSub(uint256(VaultV2(vault).epochDuration()).saturatingSub(duration)));
            (, uint48 lastPendingKey, uint208 pendingCumulativeLatest) = slot.pendingCumulative.latestCheckpoint();
            if (lastPendingKey <= fromTimestamp) {
                return 0;
            }

            return pendingCumulativeLatest
                - uint208(
                Math.max(slot.clearedPendingCursor.latest(), slot.pendingCumulative.upperLookupRecent(fromTimestamp))
            );
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getBalanceAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        unchecked {
            return index > 0
                ? getAllocatedAt(index, duration, timestamp)
                : VaultV2(vault).activeStakeAt(timestamp, "")
                    + VaultV2(vault).activeWithdrawalsForAt(duration, timestamp);
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getBalance(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            return index > 0
                ? getAllocated(index, duration)
                : VaultV2(vault).activeStake() + VaultV2(vault).activeWithdrawalsFor(duration);
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocatedAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        unchecked {
            if (duration >= VaultV2(vault).epochDuration()) {
                return 0;
            }

            uint96 parentIndex = index.getParentIndex();
            uint256 slotBalance = getBalanceAt(parentIndex, duration, timestamp);
            if (parentIndex.getDepth() != 1 || !slots[parentIndex].isShared) {
                slotBalance = slotBalance.saturatingSub(_getPrevSumAt(index, 0, timestamp));
            }
            return Math.min(slotBalance, _getPendingSizeAt(index, duration, timestamp));
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocated(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            if (duration >= VaultV2(vault).epochDuration()) {
                return 0;
            }

            uint96 parentIndex = index.getParentIndex();
            uint256 slotBalance = getBalance(parentIndex, duration);
            if (parentIndex.getDepth() != 1 || !slots[parentIndex].isShared) {
                slotBalance = slotBalance.saturatingSub(_getPrevSum(index, 0));
            }
            return Math.min(slotBalance, _getPendingSize(index, duration));
        }
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
        unchecked {
            for (
                uint32 childIndex = uint32(slots[index].firstChild.upperLookupRecent(timestamp));
                childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX;

            ) {
                uint96 childSlotIndex = index.createIndex(childIndex);
                filled += getAllocatedAt(childSlotIndex, duration, timestamp);
                childIndex = uint32(slots[childSlotIndex].nextSlot.upperLookupRecent(timestamp));
            }
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getFilled(uint96 index, uint48 duration) public view returns (uint256 filled) {
        unchecked {
            for (
                uint32 childIndex = uint32(slots[index].firstChild.latest());
                childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX;

            ) {
                uint96 childSlotIndex = index.createIndex(childIndex);
                filled += getAllocated(childSlotIndex, duration);
                childIndex = uint32(slots[childSlotIndex].nextSlot.latest());
            }
        }
    }

    /// @inheritdoc IUniversalDelegator
    function maxNetworkLimit(bytes32 subnetwork) public view returns (uint256) {
        if (_maxNetworkLimit[subnetwork].length() == 0 && __migrateTimestamp > 0) {
            // Legacy support.
            return IBaseDelegator(__oldDelegator).maxNetworkLimit(subnetwork) > 0 ? type(uint208).max : 0;
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
    function getIsNoPlugins(bytes32 subnetwork) public view returns (bool) {
        uint96 index = getSlotOfNetwork(subnetwork);
        if (index == 0) {
            revert NotAssigned();
        }
        return slots[index.getParentIndex()].noPlugins;
    }

    /// @inheritdoc IUniversalDelegator
    function getNoPluginsSize() public view returns (uint256) {
        return _noPluginsSize + _getNoPluginsPending();
    }

    /// @inheritdoc IUniversalDelegator
    function getWithdrawalBuffer() public view returns (uint256) {
        return getAllocated(WITHDRAWAL_BUFFER_INDEX, 0);
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IUniversalDelegator
    function createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noPlugins, uint128 size)
        public
        onlyRole(CREATE_SLOT_ROLE)
        returns (uint96 index)
    {
        return _createSlot(subnetworkOrOperator, parentIndex, isShared, noPlugins, size);
    }

    /// @dev Create a new slot.
    function _createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noPlugins, uint128 size)
        internal
        slotExists(parentIndex)
        syncPrevSizeSums(parentIndex)
        returns (uint96 index)
    {
        unchecked {
            if (parentIndex.getDepth() > 0 && (isShared || noPlugins)) {
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
                if (_maxNetworkLimit[subnetworkOrOperator].length() == 0 && __migrateTimestamp > 0) {
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
                _operatorToSlot[parentIndex][address(
                        bytes20(subnetworkOrOperator)
                    )].push(uint48(block.timestamp), index);
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
                if (noPlugins) {
                    if (size > VaultV2(vault).allocatable()) {
                        revert NotEnoughNoPlugins();
                    }
                    slot.noPlugins = true;
                    _noPluginsSize += size;
                }
            }

            emit CreateSlot(index, isShared, noPlugins, size);
        }
    }

    /// @inheritdoc IUniversalDelegator
    function setSize(uint96 index, uint128 newSize)
        public
        onlyRole(SET_SIZE_ROLE)
        slotExists(index)
        syncPrevSizeSums(index.getParentIndex())
    {
        unchecked {
            SlotStorage storage slot = slots[index];
            uint128 curSize = uint128(slot.size.latest());
            if (curSize == newSize) {
                return;
            }
            uint96 parentIndex = index.getParentIndex();
            SlotStorage storage parent = slots[parentIndex];

            if (newSize > curSize) {
                uint48 maxDuration = VaultV2(vault).epochDuration() - 1;
                uint256 curBalance = getBalance(parentIndex, 0);
                uint256 minBalance = getBalance(parentIndex, maxDuration);
                if (
                    !parent.isShared && _getPrevSum(index, maxDuration) + curSize < curBalance
                        && slot.nextSlot.latest() > 0 && slot.nextSlot.latest() < WITHDRAWAL_BUFFER_CHILD_INDEX
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
                if (slot.noPlugins && newSize - curSize > VaultV2(vault).allocatable()) {
                    revert NotEnoughNoPlugins();
                }
            } else {
                uint208 addPending =
                    uint208(getAllocated(index, 0).saturatingSub(getPending(index, 0)).saturatingSub(newSize));
                if (addPending > 0) {
                    parent._childrenPendingAt = uint48(block.timestamp);
                    slot.pendingCumulative.push(uint48(block.timestamp), slot.pendingCumulative.latest() + addPending);
                    if (slot.noPlugins) {
                        _noPluginsPendingCumulative.push(
                            uint48(block.timestamp), _noPluginsPendingCumulative.latest() + addPending
                        );
                    }
                }
            }
            slot.size.push(uint48(block.timestamp), newSize);
            if (slot.noPlugins) {
                _noPluginsSize = _noPluginsSize - curSize + newSize;
            }

            emit SetSize(index, newSize);
        }
    }

    /// @inheritdoc IUniversalDelegator
    function swapSlots(uint96 index1, uint96 index2)
        public
        onlyRole(SWAP_SLOTS_ROLE)
        slotExists(index1)
        slotExists(index2)
        syncPrevSizeSums(index1.getParentIndex())
    {
        unchecked {
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
                uint48 maxDuration = VaultV2(vault).epochDuration() - 1;
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

            slots[parentIndex.createIndex(slot1.prevSlot)].nextSlot
                .push(uint48(block.timestamp), index1.getChildIndex());
            if (slot2.prevSlot > 0) {
                slots[parentIndex.createIndex(uint32(slot2.prevSlot))].nextSlot
                    .push(uint48(block.timestamp), index2.getChildIndex());
            }

            emit SwapSlots(index1, index2);
        }
    }

    /// @inheritdoc IUniversalDelegator
    function removeSlot(uint96 index)
        public
        onlyRole(REMOVE_SLOT_ROLE)
        slotExists(index)
        syncPrevSizeSums(index.getParentIndex())
    {
        if (getAllocated(index, 0) > 0) {
            revert SlotAllocated();
        }

        if (index.getDepth() == 2) {
            bytes32 subnetwork = _slotToNetwork[index];
            _networkToSlot[subnetwork].push(uint48(block.timestamp), 0);
            _slotToNetwork[index] = bytes32(0);
            if (_maxNetworkLimit[subnetwork].latest() > 0) {
                _maxNetworkLimit[subnetwork].push(uint48(block.timestamp), 0);
            }
        } else if (index.getDepth() == 3) {
            _operatorToSlot[index.getParentIndex()][_slotToOperator[index]].push(uint48(block.timestamp), 0);
            _slotToOperator[index] = address(0);
        }

        // Clear no-plugins size.
        SlotStorage storage slot = slots[index];
        if (index.getDepth() == 1 && slot.noPlugins) {
            _noPluginsSize -= slot.size.latest();
        }

        _removeSlot(index);

        emit RemoveSlot(index);
    }

    /// @dev Remove a slot from the linked-list structure and mark it as non-existent.
    function _removeSlot(uint96 index) internal {
        unchecked {
            SlotStorage storage slot = slots[index];
            SlotStorage storage parent = slots[index.getParentIndex()];

            if (index.getChildIndex() == parent.firstChild.latest()) {
                uint32 nextChildIndex = uint32(slot.nextSlot.latest());
                parent.firstChild
                    .push(
                        uint48(block.timestamp),
                        index.getDepth() > 1 || nextChildIndex < WITHDRAWAL_BUFFER_CHILD_INDEX ? nextChildIndex : 0
                    );
            } else {
                slots[index.getParentIndex().createIndex(slot.prevSlot)].nextSlot
                    .push(uint48(block.timestamp), uint32(slot.nextSlot.latest()));
            }
            if (index.getChildIndex() == parent.lastChild.latest()) {
                parent.lastChild.push(uint48(block.timestamp), slot.prevSlot);
            } else {
                slots[index.getParentIndex().createIndex(uint32(slot.nextSlot.latest()))].prevSlot = slot.prevSlot;
            }
            --parent.existChildren;
            slot.exists = false;
        }
    }

    /// @inheritdoc IUniversalDelegator
    function setWithdrawalBufferSize(uint128 newWithdrawalBufferSize) public onlyRole(SET_WITHDRAWAL_BUFFER_SIZE_ROLE) {
        _withdrawalBufferSlot().size.push(uint48(block.timestamp), newWithdrawalBufferSize);

        emit SetWithdrawalBufferSize(newWithdrawalBufferSize);
    }

    /// @inheritdoc IUniversalDelegator
    function setHook(address newHook) public nonReentrant onlyRole(HOOK_SET_ROLE) {
        hook = newHook;

        emit SetHook(newHook);
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
        unchecked {
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

            _networkToSlot[subnetwork].push(uint48(block.timestamp), 0);
            _slotToNetwork[index] = bytes32(0);
            if (_maxNetworkLimit[subnetwork].latest() > 0) {
                _maxNetworkLimit[subnetwork].push(uint48(block.timestamp), 0);
            }

            if (slots[index.getParentIndex()].existChildren == 1) {
                index = index.getParentIndex();
            }
            SlotStorage storage slot = slots[index];
            SlotStorage storage parent = slots[index.getParentIndex()];

            uint208 pending = getPending(index, 0);
            if (pending > 0) {
                // Do not clear slot's pending because the slot will be completely removed anyway.

                // Clear no-plugins pending.
                if (slot.noPlugins) {
                    _clearedNoPluginsPendingCursor.push(
                        uint48(block.timestamp),
                        _getPendingCursor(_noPluginsPendingCumulative, _clearedNoPluginsPendingCursor) + pending
                    );
                }
            }

            uint208 slotSize = slot.size.latest();
            if (slotSize > 0) {
                // Do not clear slot's size because the slot will be completely removed anyway.

                // Create syncPrevSizeSums request.
                if (
                    parent.syncPrevSizeSums.latest() == 0
                        && (index.getDepth() == 1 || (!parent.isShared && slot.nextSlot.latest() > 0))
                ) {
                    parent.syncPrevSizeSums.push(uint48(block.timestamp), 1);
                }

                // Clear no-plugins size.
                if (index.getDepth() == 1 && slot.noPlugins) {
                    _noPluginsSize -= slotSize;
                }
            }

            // Remove slot to restrict from slashing.
            _removeSlot(index);

            emit ResetAllocation(index, subnetwork);
        }
    }

    /* PUBLIC FUNCTIONS (INTERNAL LOGIC) */

    /// @dev Apply slash accounting updates across the affected slot chain and invoke the optional hook.
    function onSlash(bytes32 subnetwork, address operator, uint256 amount, bytes memory data) public nonReentrant {
        unchecked {
            if (VaultV2(vault).slasher() != msg.sender) {
                revert NotSlasher();
            }

            // Adjust slot's and its parents' allocations.
            for (uint96 index = getSlotOf(subnetwork, operator); index > 0;) {
                SlotStorage storage slot = slots[index];
                SlotStorage storage parent = slots[index.getParentIndex()];

                uint208 pendingSlashed = uint208(Math.min(getPending(index, 0), amount));
                if (pendingSlashed > 0) {
                    // Clear slot's pending.
                    slot.clearedPendingCursor
                        .push(
                            uint48(block.timestamp),
                            _getPendingCursor(slot.pendingCumulative, slot.clearedPendingCursor) + pendingSlashed
                        );

                    // Clear no-plugins pending.
                    if (index.getDepth() == 1 && slot.noPlugins) {
                        _clearedNoPluginsPendingCursor.push(
                            uint48(block.timestamp),
                            _getPendingCursor(_noPluginsPendingCumulative, _clearedNoPluginsPendingCursor)
                                + pendingSlashed
                        );
                    }
                }

                uint128 sizeSlashed = uint128(Math.min(slot.size.latest(), amount - pendingSlashed));
                if (sizeSlashed > 0) {
                    // Clear slot's size.
                    slot.size.push(uint48(block.timestamp), slot.size.latest() - sizeSlashed);
                    if (
                        parent.syncPrevSizeSums.latest() == 0
                            && (index.getDepth() == 1
                                || ((index.getDepth() == 3 || !parent.isShared) && slot.nextSlot.latest() > 0))
                    ) {
                        parent.syncPrevSizeSums.push(uint48(block.timestamp), 1);
                    }

                    // Clear no-plugins size.
                    if (index.getDepth() == 1 && slot.noPlugins) {
                        _noPluginsSize -= sizeSlashed;
                    }
                }
                index = index.getParentIndex();
            }

            // Make a call to the custom hook.
            address hook_ = hook;
            if (hook_ != address(0)) {
                bytes memory hookCalldata = abi.encodeCall(IDelegatorHook.onSlash, (subnetwork, operator, amount, data));

                if (gasleft() < HOOK_RESERVE + HOOK_GAS_LIMIT * 64 / 63) {
                    revert InsufficientHookGas();
                }

                assembly ("memory-safe") {
                    pop(call(HOOK_GAS_LIMIT, hook_, 0, add(hookCalldata, 0x20), mload(hookCalldata), 0, 0))
                }
            }

            emit OnSlash(subnetwork, operator, amount);
        }
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

        hook = params.hook;

        _withdrawalBufferSlot().size.push(uint48(block.timestamp), params.withdrawalBufferSize);

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(HOOK_SET_ROLE, params.hookSetRoleHolder);
        _grantRoleIfNotZero(CREATE_SLOT_ROLE, params.createSlotRoleHolder);
        _grantRoleIfNotZero(SET_SIZE_ROLE, params.setSizeRoleHolder);
        _grantRoleIfNotZero(SWAP_SLOTS_ROLE, params.swapSlotsRoleHolder);

        emit Initialize(params);
    }

    /* MIGRATION */

    /// @dev Migrate delegator state from the previously configured delegator.
    function migrate(address oldDelegator) public {
        if (vault != msg.sender) {
            revert NotVault();
        }
        __migrateTimestamp = uint48(block.timestamp);
        __oldDelegator = oldDelegator;

        _createSlot(
            bytes32(0),
            0,
            IEntity(oldDelegator).TYPE() < OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE,
            true,
            uint128(Math.min(VaultV2(vault).allocatable(), type(uint128).max))
        );
    }

    /* UTILITY FUNCTIONS */

    function _getPendingSizeAt(uint96 index, uint48 duration, uint48 timestamp) internal view returns (uint208) {
        unchecked {
            return slots[index].size.upperLookupRecent(timestamp) + getPendingAt(index, duration, timestamp);
        }
    }

    function _getPendingSize(uint96 index, uint48 duration) internal view returns (uint208) {
        unchecked {
            return slots[index].size.latest() + getPending(index, duration);
        }
    }

    function _getPrevSizeSumAt(uint96 index, uint48 timestamp) internal view returns (uint208 prevSizeSum) {
        unchecked {
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
    }

    function _getPrevSizeSum(uint96 index) internal view returns (uint208 prevSizeSum) {
        unchecked {
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
    }

    function _getPrevPendingSumAt(uint96 index, uint48 duration, uint48 timestamp)
        internal
        view
        returns (uint208 prevPendingSum)
    {
        unchecked {
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
    }

    function _getPrevPendingSum(uint96 index, uint48 duration) internal view returns (uint208 prevPendingSum) {
        unchecked {
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
                    <= block.timestamp.saturatingSub(uint256(VaultV2(vault).epochDuration()).saturatingSub(duration))
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
    }

    function _getPrevSumAt(uint96 index, uint48 duration, uint48 timestamp) internal view returns (uint208) {
        unchecked {
            return _getPrevSizeSumAt(index, timestamp) + _getPrevPendingSumAt(index, duration, timestamp);
        }
    }

    function _getPrevSum(uint96 index, uint48 duration) internal view returns (uint208) {
        unchecked {
            return _getPrevSizeSum(index) + _getPrevPendingSum(index, duration);
        }
    }

    /// @dev Return pending no-plugins allocation over the current slashable window.
    function _getNoPluginsPending() internal view returns (uint208) {
        unchecked {
            uint48 fromTimestamp = uint48(block.timestamp.saturatingSub(uint256(VaultV2(vault).epochDuration())));
            return _noPluginsPendingCumulative.latest()
                - uint208(
                Math.max(
                _clearedNoPluginsPendingCursor.latest(), _noPluginsPendingCumulative.upperLookupRecent(fromTimestamp)
            )
            );
        }
    }

    function _getPendingCursor(
        Checkpoints.Trace208 storage pendingCumulative,
        Checkpoints.Trace208 storage clearedCursor
    ) internal view returns (uint208) {
        return uint208(
            Math.max(
                clearedCursor.latest(),
                pendingCumulative.upperLookupRecent(
                    uint48(block.timestamp.saturatingSub(VaultV2(vault).epochDuration()))
                )
            )
        );
    }

    /// @dev Return storage pointer to the withdrawal buffer slot.
    function _withdrawalBufferSlot() internal view returns (SlotStorage storage) {
        return slots[WITHDRAWAL_BUFFER_INDEX];
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}

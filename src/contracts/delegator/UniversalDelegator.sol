// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

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
    MAX_GROUPS,
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
import {IVaultV2, VAULT_V2_VERSION} from "../../interfaces/vault/IVaultV2.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";

/// @title UniversalDelegator
/// @notice Contract for hierarchical stake allocation across groups, networks, and operators.
contract UniversalDelegator is
    Entity,
    StaticDelegateCallable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IUniversalDelegator
{
    using UniversalDelegatorIndex for uint96;
    using Checkpoints for Checkpoints.Trace208;
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;

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
        Checkpoints.Trace208 size;
        Checkpoints.Trace208 prevSum;
        Checkpoints.Trace208 nextSlot;
        Checkpoints.Trace208 lastChild;
        Checkpoints.Trace208 firstChild;
        Checkpoints.Trace208 needPrevSumsSync;
        Checkpoints.Trace208 pendingCumulative;
        Checkpoints.Trace208 clearedPendingCumulative;
        Checkpoints.Trace208 childrenPendingCumulative;
        Checkpoints.Trace208 clearedChildrenPendingCumulative;
    }

    /// @inheritdoc IUniversalDelegator
    address public vault;
    /// @inheritdoc IUniversalDelegator
    address public hook;

    /// @dev Total slot size marked as no-plugins across root groups.
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
    /// @dev Cumulative slashed amounts per slot.
    mapping(uint96 index => Checkpoints.Trace208 amount) internal _cumulativeSlash;
    /// @dev Cumulative pending no-plugins amounts.
    Checkpoints.Trace208 internal _noPluginsPendingCumulative;
    /// @dev Cumulative cleared pending no-plugins amounts.
    Checkpoints.Trace208 internal _clearedNoPluginsPendingCumulative;

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

    modifier syncPrevSums(uint96 parentIndex) {
        if (slots[parentIndex].needPrevSumsSync.latest() > 0) {
            _syncPrevSums(parentIndex);
            slots[parentIndex].needPrevSumsSync.push(uint48(block.timestamp), 0);
        }
        _;
        _syncPrevSums(parentIndex);
    }

    /// @dev Synchronize cumulative child prefix sums for a parent slot.
    function _syncPrevSums(uint96 parentIndex) internal {
        unchecked {
            uint208 prevSum;
            for (uint32 childIndex = uint32(slots[parentIndex].firstChild.latest()); childIndex > 0;) {
                SlotStorage storage child = slots[parentIndex.createIndex(childIndex)];
                if (child.prevSum.latest() != prevSum) {
                    child.prevSum.push(uint48(block.timestamp), prevSum);
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
        return getAllocatedAt(subnetwork, operator, duration, timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        return getAllocated(subnetwork, operator, duration);
    }

    /// @inheritdoc IUniversalDelegator
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        public
        view
        returns (uint256)
    {
        if (timestamp < __migrateTimestamp) {
            return IBaseDelegator(__oldDelegator).stakeAt(subnetwork, operator, timestamp, hints);
        }
        return getAllocatedAt(subnetwork, operator, IVaultV2(vault).epochDuration(), timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function stake(bytes32 subnetwork, address operator) public view returns (uint256) {
        return getAllocated(subnetwork, operator, IVaultV2(vault).epochDuration());
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
            prevSum: _getPrevSum(index)
        });
    }

    /// @inheritdoc IUniversalDelegator
    function getChildrenPendingAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint208) {
        unchecked {
            SlotStorage storage slot = slots[index];
            uint48 fromTimestamp = uint48(
                uint256(timestamp).saturatingSub(uint256(IVaultV2(vault).epochDuration()).saturatingSub(duration))
            );
            return uint208(
                uint256(
                        slot.childrenPendingCumulative.upperLookupRecent(timestamp)
                            - slot.childrenPendingCumulative.upperLookupRecent(fromTimestamp)
                    )
                    .saturatingSub(
                        slot.clearedChildrenPendingCumulative.upperLookupRecent(timestamp)
                            - slot.clearedChildrenPendingCumulative.upperLookupRecent(fromTimestamp)
                    )
            );
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getChildrenPending(uint96 index, uint48 duration) public view returns (uint208) {
        unchecked {
            SlotStorage storage slot = slots[index];
            uint48 fromTimestamp =
                uint48(block.timestamp.saturatingSub(uint256(IVaultV2(vault).epochDuration()).saturatingSub(duration)));
            return uint208(
                uint256(
                        slot.childrenPendingCumulative.latest()
                            - slot.childrenPendingCumulative.upperLookupRecent(fromTimestamp)
                    )
                    .saturatingSub(
                        slot.clearedChildrenPendingCumulative.latest()
                            - slot.clearedChildrenPendingCumulative.upperLookupRecent(fromTimestamp)
                    )
            );
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getPendingAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint208) {
        unchecked {
            SlotStorage storage slot = slots[index];
            uint48 fromTimestamp = uint48(
                uint256(timestamp).saturatingSub(uint256(IVaultV2(vault).epochDuration()).saturatingSub(duration))
            );
            return uint208(
                uint256(
                        slot.pendingCumulative.upperLookupRecent(timestamp)
                            - slot.pendingCumulative.upperLookupRecent(fromTimestamp)
                    )
                    .saturatingSub(
                        slot.clearedPendingCumulative.upperLookupRecent(timestamp)
                            - slot.clearedPendingCumulative.upperLookupRecent(fromTimestamp)
                    )
            );
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getPending(uint96 index, uint48 duration) public view returns (uint208) {
        unchecked {
            SlotStorage storage slot = slots[index];
            uint48 fromTimestamp =
                uint48(block.timestamp.saturatingSub(uint256(IVaultV2(vault).epochDuration()).saturatingSub(duration)));
            return uint208(
                uint256(slot.pendingCumulative.latest() - slot.pendingCumulative.upperLookupRecent(fromTimestamp))
                    .saturatingSub(
                        slot.clearedPendingCumulative.latest()
                            - slot.clearedPendingCumulative.upperLookupRecent(fromTimestamp)
                    )
            );
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getBalanceAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        unchecked {
            return index > 0
                ? getAllocatedAt(index, duration, timestamp)
                : IVaultV2(vault).activeStakeAt(timestamp, "")
                    + IVaultV2(vault).activeWithdrawalsForAt(duration, timestamp);
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getBalance(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            return index > 0
                ? getAllocated(index, duration)
                : IVaultV2(vault).activeStake() + IVaultV2(vault).activeWithdrawalsFor(duration);
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getAvailableAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        return getBalanceAt(index, duration, timestamp).saturatingSub(getChildrenPendingAt(index, duration, timestamp));
    }

    /// @inheritdoc IUniversalDelegator
    function getAvailable(uint96 index, uint48 duration) public view returns (uint256) {
        return getBalance(index, duration).saturatingSub(getChildrenPending(index, duration));
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocatedAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        unchecked {
            if (duration > IVaultV2(vault).epochDuration()) {
                return 0;
            }

            uint96 parentIndex = index.getParentIndex();
            uint256 slotAvailable = getAvailableAt(parentIndex, duration, timestamp);
            if (!slots[parentIndex].isShared) {
                slotAvailable = slotAvailable.saturatingSub(_getPrevSumAt(index, timestamp));
            }
            // The current allocation of the slot + the pending allocation (to support slashing w/o captureTimestamp).
            return Math.min(slotAvailable, slots[index].size.upperLookupRecent(timestamp))
                + getPendingAt(index, duration, timestamp);
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocated(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            if (duration > IVaultV2(vault).epochDuration()) {
                return 0;
            }

            uint96 parentIndex = index.getParentIndex();
            uint256 slotAvailable = getAvailable(parentIndex, duration);
            if (!slots[parentIndex].isShared) {
                slotAvailable = slotAvailable.saturatingSub(_getPrevSum(index));
            }
            return Math.min(slotAvailable, slots[index].size.latest()) + getPending(index, duration);
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
    function getFilledAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        unchecked {
            uint96 lastIndex = index.createIndex(uint32(slots[index].lastChild.upperLookupRecent(timestamp)));
            return Math.min(
                _getPrevSumAt(lastIndex, timestamp) + slots[lastIndex].size.upperLookupRecent(timestamp)
                    + getChildrenPendingAt(index, duration, timestamp),
                getBalanceAt(index, duration, timestamp)
            );
        }
    }

    /// @inheritdoc IUniversalDelegator
    function getFilled(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            uint96 lastIndex = index.createIndex(uint32(slots[index].lastChild.latest()));
            return Math.min(
                _getPrevSum(lastIndex) + slots[lastIndex].size.latest() + getChildrenPending(index, duration),
                getBalance(index, duration)
            );
        }
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
        slotExists(parentIndex)
        syncPrevSums(parentIndex)
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
                            ? MAX_GROUPS
                            : parentIndex.getDepth() == 1 ? MAX_NETWORKS : MAX_OPERATORS)
            ) {
                revert TooManyChildren();
            }
            ++parent.totalChildren;

            index = parentIndex.createIndex(parent.existChildren);

            if (parentIndex.getDepth() == 1) {
                if (_networkToSlot[subnetworkOrOperator].latest() > 0) {
                    revert AlreadyAssigned();
                }
                _networkToSlot[subnetworkOrOperator].push(uint48(block.timestamp), index);
                _slotToNetwork[index] = subnetworkOrOperator;
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
                    if (size > IVaultV2(vault).allocatable()) {
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
        syncPrevSums(index.getParentIndex())
        returns (uint208 pending)
    {
        unchecked {
            SlotStorage storage slot = slots[index];
            uint128 curSize = uint128(slot.size.latest());
            if (curSize == newSize) {
                return 0;
            }
            SlotStorage storage parent = slots[index.getParentIndex()];
            uint256 available = getAvailable(index.getParentIndex(), 0);

            if (newSize > curSize) {
                if (
                    !parent.isShared && slot.prevSum.latest() + curSize < available && slot.nextSlot.latest() > 0
                        && slot.nextSlot.latest() < WITHDRAWAL_BUFFER_CHILD_INDEX
                ) {
                    SlotStorage storage lastChild =
                        slots[index.getParentIndex().createIndex(uint32(parent.lastChild.latest()))];
                    if (
                        newSize - curSize
                            > available.saturatingSub(lastChild.prevSum.latest() + lastChild.size.latest())
                    ) {
                        revert NotEnoughAvailable();
                    }
                }
                if (slot.noPlugins && newSize - curSize > IVaultV2(vault).allocatable()) {
                    revert NotEnoughNoPlugins();
                }
            } else {
                if (!parent.isShared && slot.prevSum.latest() < available) {
                    pending = uint208((getAllocated(index, 0) - getPending(index, 0)).saturatingSub(newSize));
                    if (pending > 0) {
                        parent.childrenPendingCumulative
                            .push(uint48(block.timestamp), parent.childrenPendingCumulative.latest() + pending);
                        slot.pendingCumulative.push(uint48(block.timestamp), slot.pendingCumulative.latest() + pending);
                        if (slot.noPlugins) {
                            _noPluginsPendingCumulative.push(
                                uint48(block.timestamp), _noPluginsPendingCumulative.latest() + pending
                            );
                        }
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
        syncPrevSums(index1.getParentIndex())
    {
        unchecked {
            SlotStorage storage parent = slots[index1.getParentIndex()];
            SlotStorage storage slot1 = slots[index1];
            SlotStorage storage slot2 = slots[index2];
            uint256 available = getAvailable(index1.getParentIndex(), 0);
            bool isAllocated = slot1.prevSum.latest() < available;
            uint96 parentIndex = index1.getParentIndex();

            if (parentIndex != index2.getParentIndex()) {
                revert NotSameParent();
            }
            if (parent.isShared) {
                revert IsShared();
            }
            if (isAllocated != (slot2.prevSum.latest() < available)) {
                revert NotSameAllocated();
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
            if (isAllocated && slot2.prevSum.latest() + slot2.size.latest() > available) {
                revert PartiallyAllocated();
            }

            if (index1.getChildIndex() == parent.firstChild.latest()) {
                parent.firstChild.push(uint48(block.timestamp), index2.getChildIndex());
            }
            if (index2.getChildIndex() == parent.lastChild.latest()) {
                parent.lastChild.push(uint48(block.timestamp), index1.getChildIndex());
            }

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
        syncPrevSums(index.getParentIndex())
    {
        if (getAllocated(index, 0) > 0) {
            revert SlotAllocated();
        }

        if (_slotToNetwork[index] != bytes32(0)) {
            _networkToSlot[_slotToNetwork[index]].push(uint48(block.timestamp), 0);
            _slotToNetwork[index] = bytes32(0);
        } else if (_slotToOperator[index] != address(0)) {
            _operatorToSlot[index.getParentIndex()][_slotToOperator[index]].push(uint48(block.timestamp), 0);
            _slotToOperator[index] = address(0);
        }

        _removeSlot(index);
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

            emit RemoveSlot(index);
        }
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

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

            if (slots[index.getParentIndex()].existChildren == 1) {
                index = index.getParentIndex();
            }
            SlotStorage storage slot = slots[index];
            SlotStorage storage parent = slots[index.getParentIndex()];

            uint208 pending = getPending(index, 0);
            if (pending > 0) {
                // Do not clear slot's pending because the slot will be completely removed anyway.

                // Clear parent's children-pending for slot.
                parent.clearedChildrenPendingCumulative
                    .push(uint48(block.timestamp), parent.clearedChildrenPendingCumulative.latest() + pending);

                // Clear no-plugins pending.
                if (slot.noPlugins) {
                    uint208 noPluginsPending = _getNoPluginsPending();
                    if (noPluginsPending > 0) {
                        _clearedNoPluginsPendingCumulative.push(
                            uint48(block.timestamp), _clearedNoPluginsPendingCumulative.latest() + noPluginsPending
                        );
                    }
                }
            }

            uint208 slotSize = slot.size.latest();
            if (slotSize > 0) {
                // Clear slot's size.
                slot.size.push(uint48(block.timestamp), 0);
                parent.needPrevSumsSync.push(uint48(block.timestamp), 1);

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

    /// @dev Apply slash accounting updates across the affected slot chain and invoke the optional hook.
    function onSlash(bytes32 subnetwork, address operator, uint256 amount, bytes memory data) public nonReentrant {
        unchecked {
            if (IVault(vault).slasher() != msg.sender) {
                revert NotSlasher();
            }

            // Adjust slot's and its parents' allocations.
            for (uint96 index = getSlotOf(subnetwork, operator); index > 0;) {
                SlotStorage storage slot = slots[index];
                uint208 pendingSlashed = uint208(Math.min(getPending(index, 0), amount));
                if (pendingSlashed > 0) {
                    // Clear slot's pending.
                    slot.clearedPendingCumulative
                        .push(uint48(block.timestamp), slot.clearedPendingCumulative.latest() + pendingSlashed);

                    // Clear parent's children-pending.
                    slots[index.getParentIndex()].clearedChildrenPendingCumulative
                        .push(
                            uint48(block.timestamp),
                            slots[index.getParentIndex()].clearedChildrenPendingCumulative.latest() + pendingSlashed
                        );

                    // Clear no-plugins pending.
                    if (index.getDepth() == 1 && slot.noPlugins) {
                        _clearedNoPluginsPendingCumulative.push(
                            uint48(block.timestamp), _clearedNoPluginsPendingCumulative.latest() + pendingSlashed
                        );
                    }
                }

                uint128 sizeSlashed = uint128(Math.min(slot.size.latest(), amount - pendingSlashed));
                if (sizeSlashed > 0) {
                    // Clear slot's size.
                    slot.size.push(uint48(block.timestamp), slot.size.latest() - sizeSlashed);
                    slots[index.getParentIndex()].needPrevSumsSync.push(uint48(block.timestamp), 1);

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
    function migrate() public {
        if (IMigratableEntity(vault).version() != VAULT_V2_VERSION) {
            revert WrongMigrate();
        }
        if (IEntity(IVaultV2(vault).delegator()).TYPE() == TYPE) {
            revert NotMigrating();
        }
        __migrateTimestamp = uint48(block.timestamp);
        __oldDelegator = IVaultV2(vault).delegator();

        // TODO: more smooth migration.
        _rootSlot().childrenPendingCumulative.push(uint48(block.timestamp), type(uint128).max);
        _noPluginsPendingCumulative.push(uint48(block.timestamp), type(uint128).max);
    }

    /* DEPRECATED FUNCTIONS */

    /// @inheritdoc IUniversalDelegator
    function maxNetworkLimit(bytes32) public pure returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IUniversalDelegator
    function setMaxNetworkLimit(uint96, uint256) public {}

    /* UTILITY FUNCTIONS */

    function _getPrevSumAt(uint96 index, uint48 timestamp) internal view returns (uint208 prevSum) {
        if (index == 0) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        if (parent.needPrevSumsSync.upperLookupRecent(timestamp) == 0) {
            return slots[index].prevSum.upperLookupRecent(timestamp);
        }
        for (uint32 childIndex = uint32(parent.firstChild.upperLookupRecent(timestamp)); childIndex > 0;) {
            uint96 curIndex = parentIndex.createIndex(childIndex);
            if (index == curIndex) {
                break;
            }
            SlotStorage storage child = slots[curIndex];
            prevSum += child.size.upperLookupRecent(timestamp);
            childIndex = uint32(child.nextSlot.upperLookupRecent(timestamp));
        }
    }

    function _getPrevSum(uint96 index) internal view returns (uint208 prevSum) {
        if (index == 0) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        if (parent.needPrevSumsSync.latest() == 0) {
            return slots[index].prevSum.latest();
        }
        for (uint32 childIndex = uint32(parent.firstChild.latest()); childIndex > 0;) {
            uint96 curIndex = parentIndex.createIndex(childIndex);
            if (index == curIndex) {
                break;
            }
            SlotStorage storage child = slots[curIndex];
            prevSum += child.size.latest();
            childIndex = uint32(child.nextSlot.latest());
        }
    }

    /// @dev Return pending no-plugins allocation over the current slashable window.
    function _getNoPluginsPending() internal view returns (uint208) {
        unchecked {
            uint48 fromTimestamp = uint48(block.timestamp.saturatingSub(uint256(IVaultV2(vault).epochDuration())));
            return uint208(
                uint256(
                        _noPluginsPendingCumulative.latest()
                            - _noPluginsPendingCumulative.upperLookupRecent(fromTimestamp)
                    )
                    .saturatingSub(
                        _clearedNoPluginsPendingCumulative.latest()
                            - _clearedNoPluginsPendingCumulative.upperLookupRecent(fromTimestamp)
                    )
            );
        }
    }

    /// @dev Return storage pointer to the root slot.
    function _rootSlot() internal view returns (SlotStorage storage) {
        return slots[0];
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

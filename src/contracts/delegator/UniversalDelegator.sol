// SPDX-License-Identifier: BUSL-1.1
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
    CREATE_SLOT_ROLE,
    HOOK_GAS_LIMIT,
    HOOK_RESERVE,
    HOOK_SET_ROLE,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE,
    WITHDRAWAL_BUFFER_CHILD_INDEX,
    WITHDRAWAL_BUFFER_INDEX,
    MAX_GROUPS,
    MAX_NETWORKS,
    MAX_OPERATORS
} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {Multicallable as MulticallUpgradeable} from "@solady/src/utils/Multicallable.sol";

contract UniversalDelegator is
    Entity,
    StaticDelegateCallable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    MulticallUpgradeable,
    IUniversalDelegator
{
    using UniversalDelegatorIndex for uint96;
    using Checkpoints for Checkpoints.Trace208;
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;

    address internal immutable NETWORK_REGISTRY;
    address internal immutable VAULT_FACTORY;
    address internal immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc IUniversalDelegator
     */
    address public vault;

    /**
     * @inheritdoc IUniversalDelegator
     */
    address public hook;

    uint208 internal _noPluginsSize;

    // @dev index is {32 bytes of child index at depth 1}{32 bytes - depth 2}{32 bytes - depth 3}
    mapping(uint96 index => SlotStorage slot) internal slots;
    mapping(bytes32 subnetwork => Checkpoints.Trace208) internal _networkToSlot;
    mapping(uint96 index => bytes32 subnetwork) internal _slotToNetwork;
    mapping(uint96 parentIndex => mapping(address operator => Checkpoints.Trace208)) internal _operatorToSlot;
    mapping(uint96 index => address operator) internal _slotToOperator;
    mapping(uint96 index => Checkpoints.Trace208 amount) internal _cumulativeSlash;
    Checkpoints.Trace208 internal _noPluginsPendingCumulative;
    Checkpoints.Trace208 internal _clearedNoPluginsPendingCumulative;

    uint48 internal __migrateTimestamp;
    address internal __oldDelegator;

    struct SlotStorage {
        bool exists;
        uint32 nextSlot;
        uint32 prevSlot;
        uint32 numChildren;
        uint32 firstChild;
        uint32 lastChild;
        uint32 numNetworks;
        bool isShared;
        bool noPlugins;
        bool needPrevSumsSync;
        Checkpoints.Trace208 size;
        Checkpoints.Trace208 prevSum;
        Checkpoints.Trace208 pendingCumulative;
        Checkpoints.Trace208 clearedPendingCumulative;
        Checkpoints.Trace208 childrenPendingCumulative;
        Checkpoints.Trace208 clearedChildrenPendingCumulative;
    }

    modifier slotExists(uint96 index) {
        if (index > 0 && !slots[index].exists) {
            revert SlotNotCreated();
        }
        _;
    }

    modifier syncPrevSums(uint96 parentIndex) {
        if (slots[parentIndex].needPrevSumsSync) {
            _syncPrevSums(parentIndex);
            slots[parentIndex].needPrevSumsSync = false;
        }
        _;
        _syncPrevSums(parentIndex);
    }

    function _syncPrevSums(uint96 parentIndex) internal {
        uint208 prevSum;
        for (uint32 childIndex = slots[parentIndex].firstChild; childIndex > 0;) {
            SlotStorage storage child = slots[parentIndex.createIndex(childIndex)];
            if (child.prevSum.latest() != prevSum) {
                child.prevSum.push(uint48(block.timestamp), prevSum);
            }
            prevSum += child.size.latest();
            childIndex = child.nextSlot;
        }
    }

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

    /**
     * @inheritdoc IUniversalDelegator
     */
    function VERSION() public pure returns (uint64) {
        return 2;
    }

    /* VIEW FUNCTIONS */

    /**
     * @inheritdoc IUniversalDelegator
     */
    function stakeForAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        public
        view
        returns (uint256)
    {
        return getAllocatedAt(subnetwork, operator, timestamp, duration);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        return getAllocated(subnetwork, operator, duration);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        public
        view
        returns (uint256)
    {
        if (timestamp < __migrateTimestamp) {
            return IBaseDelegator(__oldDelegator).stakeAt(subnetwork, operator, timestamp, hints);
        }

        return getAllocatedAt(subnetwork, operator, timestamp, IVaultV2(vault).epochDuration());
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function stake(bytes32 subnetwork, address operator) public view returns (uint256) {
        return getAllocated(subnetwork, operator, IVaultV2(vault).epochDuration());
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getSlot(uint96 index) public view returns (Slot memory) {
        return Slot({
            exists: slots[index].exists,
            nextSlot: slots[index].nextSlot,
            prevSlot: slots[index].prevSlot,
            numChildren: slots[index].numChildren,
            firstChild: slots[index].firstChild,
            lastChild: slots[index].lastChild,
            isShared: slots[index].isShared,
            noPlugins: slots[index].noPlugins,
            size: uint128(slots[index].size.latest()),
            prevSum: slots[index].prevSum.latest(),
            childrenPendingCumulative: slots[index].childrenPendingCumulative.latest()
        });
    }

    function getChildrenPendingAt(uint96 index, uint48 timestamp, uint48 duration) public view returns (uint208) {
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

    function getPendingAt(uint96 index, uint48 timestamp, uint48 duration) public view returns (uint208) {
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

    /**
     * @inheritdoc IUniversalDelegator
     * @dev Returns the collateral balance of a given slot.
     */
    function getBalanceAt(uint96 index, uint48 timestamp, uint48 duration) public view returns (uint256) {
        unchecked {
            if (index == 0) {
                return IVaultV2(vault).activeStakeAt(timestamp, "")
                    + IVaultV2(vault).activeWithdrawalsForAt(duration, timestamp);
            }
            return getAllocatedAt(index, timestamp, duration);
        }
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getBalance(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            if (index == 0) {
                return IVaultV2(vault).activeStake() + IVaultV2(vault).activeWithdrawalsFor(duration);
            }
            return getAllocated(index, duration);
        }
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev Returns the available to allocate balance in the given slot.
     */
    function getAvailableAt(uint96 index, uint48 timestamp, uint48 duration) public view returns (uint256) {
        return getBalanceAt(index, timestamp, duration).saturatingSub(getChildrenPendingAt(index, timestamp, duration));
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAvailable(uint96 index, uint48 duration) public view returns (uint256) {
        return getBalance(index, duration).saturatingSub(getChildrenPending(index, duration));
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev Returns the allocation of the given slot.
     */
    function getAllocatedAt(uint96 index, uint48 timestamp, uint48 duration) public view returns (uint256) {
        unchecked {
            if (duration > IVaultV2(vault).epochDuration()) {
                return 0;
            }

            SlotStorage storage slot = slots[index];
            uint96 parentIndex = index.getParentIndex();
            SlotStorage storage parent = slots[parentIndex];
            uint256 prevSum;
            if (parent.needPrevSumsSync) {
                for (uint32 childIndex = parent.firstChild; childIndex > 0;) {
                    uint96 currentIndex = parentIndex.createIndex(childIndex);
                    if (index == currentIndex) {
                        break;
                    }
                    SlotStorage storage child = slots[currentIndex];
                    prevSum += child.size.upperLookupRecent(timestamp);
                    childIndex = child.nextSlot;
                }
            } else {
                prevSum = slot.prevSum.upperLookupRecent(timestamp);
            }

            uint256 slotAvailable = getAvailableAt(parentIndex, timestamp, duration);
            if (!parent.isShared) {
                slotAvailable = slotAvailable.saturatingSub(prevSum);
            }
            // the current allocation of the slot + the pending allocation (to support slashing w/o captureTimestamp)
            return
                Math.min(slotAvailable, slot.size.upperLookupRecent(timestamp))
                    + getPendingAt(index, timestamp, duration);
        }
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAllocated(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            if (duration > IVaultV2(vault).epochDuration()) {
                return 0;
            }

            SlotStorage storage slot = slots[index];
            uint96 parentIndex = index.getParentIndex();
            SlotStorage storage parent = slots[parentIndex];
            uint256 prevSum;
            if (parent.needPrevSumsSync) {
                for (uint32 childIndex = parent.firstChild; childIndex > 0;) {
                    uint96 currentIndex = parentIndex.createIndex(childIndex);
                    SlotStorage storage child = slots[currentIndex];
                    if (index == currentIndex) {
                        break;
                    }
                    prevSum += child.size.latest();
                    childIndex = child.nextSlot;
                }
            } else {
                prevSum = slot.prevSum.latest();
            }

            uint256 slotAvailable = getAvailable(parentIndex, duration);
            if (!parent.isShared) {
                slotAvailable = slotAvailable.saturatingSub(prevSum);
            }
            return Math.min(slotAvailable, slot.size.latest()) + getPending(index, duration);
        }
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 timestamp, uint48 duration)
        public
        view
        returns (uint256)
    {
        uint96 index = getSlotOfAt(subnetwork, operator, timestamp);
        return index > 0 ? getAllocatedAt(index, timestamp, duration) : 0;
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAllocated(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        uint96 index = getSlotOf(subnetwork, operator);
        return index > 0 ? getAllocated(index, duration) : 0;
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getSlotOfNetworkAt(bytes32 subnetwork, uint48 timestamp) public view returns (uint96) {
        return uint96(_networkToSlot[subnetwork].upperLookupRecent(timestamp));
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getSlotOfNetwork(bytes32 subnetwork) public view returns (uint96) {
        return uint96(_networkToSlot[subnetwork].latest());
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getSlotOfOperatorAt(uint96 parentIndex, address operator, uint48 timestamp) public view returns (uint96) {
        return uint96(_operatorToSlot[parentIndex][operator].upperLookupRecent(timestamp));
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getSlotOfOperator(uint96 parentIndex, address operator) public view returns (uint96) {
        return uint96(_operatorToSlot[parentIndex][operator].latest());
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp) public view returns (uint96) {
        return getSlotOfOperatorAt(getSlotOfNetworkAt(subnetwork, timestamp), operator, timestamp);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getSlotOf(bytes32 subnetwork, address operator) public view returns (uint96) {
        return getSlotOfOperator(getSlotOfNetwork(subnetwork), operator);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getIsShared(bytes32 subnetwork) public view returns (bool) {
        uint96 index = getSlotOfNetwork(subnetwork);
        if (index == 0) {
            revert NotAssigned();
        }
        return slots[index.getParentIndex()].isShared;
    }

    function getIsNoPlugins(bytes32 subnetwork) public view returns (bool) {
        uint96 index = getSlotOfNetwork(subnetwork);
        if (index == 0) {
            revert NotAssigned();
        }
        return slots[index.getParentIndex()].noPlugins;
    }

    function getNoPluginsSize() public view returns (uint208) {
        return _noPluginsSize + _getNoPluginsPending();
    }

    function getWithdrawalBuffer() public view returns (uint256) {
        return getAllocated(WITHDRAWAL_BUFFER_INDEX, 0);
    }

    // TODO: add isFirst()?

    /* CURATOR FUNCTIONS */

    /**
     * @inheritdoc IUniversalDelegator
     */
    function createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noPlugins, uint128 size)
        public
        onlyRole(CREATE_SLOT_ROLE)
        slotExists(parentIndex)
        returns (uint96)
    {
        if (parentIndex.getDepth() > 0 && (isShared || noPlugins)) {
            revert WrongDepth();
        }

        SlotStorage storage parent = slots[parentIndex];
        if (
            ++parent.numChildren
                > (parentIndex.getDepth() == 0
                        ? MAX_GROUPS
                        : parentIndex.getDepth() == 1 ? MAX_NETWORKS : MAX_OPERATORS)
        ) {
            revert TooManyChildren();
        }

        uint96 index = parentIndex.createIndex(parent.numChildren);

        if (parentIndex.getDepth() == 1) {
            if (_networkToSlot[subnetworkOrOperator].latest() != 0) {
                revert AlreadyAssigned();
            }
            _networkToSlot[subnetworkOrOperator].push(uint48(block.timestamp), index);
            _slotToNetwork[index] = subnetworkOrOperator;
        } else if (parentIndex.getDepth() == 2) {
            if (_operatorToSlot[parentIndex][address(bytes20(subnetworkOrOperator))].latest() != 0) {
                revert AlreadyAssigned();
            }
            _operatorToSlot[parentIndex][address(bytes20(subnetworkOrOperator))].push(uint48(block.timestamp), index);
            _slotToOperator[index] = address(bytes20(subnetworkOrOperator));
        }

        SlotStorage storage slot = slots[index];

        if (parent.firstChild == 0) {
            parent.firstChild = index.getChildIndex();
        } else {
            slot.prevSlot = parent.lastChild;
            slots[parentIndex.createIndex(parent.lastChild)].nextSlot = index.getChildIndex();
        }
        parent.lastChild = index.getChildIndex();
        if (size > 0) {
            slot.size.push(uint48(block.timestamp), size);
        }
        slot.exists = true;

        if (parentIndex.getDepth() == 0) {
            slots[index].nextSlot = WITHDRAWAL_BUFFER_CHILD_INDEX;
            slot.isShared = isShared;
            if (noPlugins) {
                if (size > IVaultV2(vault).allocatable()) {
                    revert NotEnoughNoPlugins();
                }
                slot.noPlugins = true;
                _noPluginsSize += size;
            }
        }
        if (parentIndex.getDepth() == 1) {
            ++parent.numNetworks;
        }

        _syncPrevSums(parentIndex);

        emit CreateSlot(index, isShared, noPlugins, size);

        return index;
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev if size increase: just change the size if slot not fully allocated or last child, otherwise use unallocated funds
     *      if size decrease: just change the size if slot not allocated, otherwise increase pending free
     */
    function setSize(uint96 index, uint128 newSize)
        public
        onlyRole(SET_SIZE_ROLE)
        slotExists(index)
        syncPrevSums(index.getParentIndex())
        returns (uint208 pending)
    {
        SlotStorage storage slot = slots[index];
        uint208 currentSize = slot.size.latest();
        if (currentSize == newSize) {
            return 0;
        }
        SlotStorage storage parent = slots[index.getParentIndex()];
        uint256 available = getAvailable(index.getParentIndex(), 0);

        if (newSize > currentSize) {
            if (
                !parent.isShared && slot.prevSum.latest() + currentSize < available && slot.nextSlot > 0
                    && slot.nextSlot != WITHDRAWAL_BUFFER_CHILD_INDEX
            ) {
                SlotStorage storage lastChild = slots[index.getParentIndex().createIndex(parent.lastChild)];
                if (
                    newSize - currentSize
                        > available.saturatingSub(lastChild.prevSum.latest() + lastChild.size.latest())
                ) {
                    revert NotEnoughAvailable();
                }
            }
            if (slot.noPlugins && newSize - currentSize > IVaultV2(vault).allocatable()) {
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
            unchecked {
                _noPluginsSize = _noPluginsSize - currentSize + newSize;
            }
        }

        emit SetSize(index, newSize);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function swapSlots(uint96 index1, uint96 index2)
        public
        onlyRole(SWAP_SLOTS_ROLE)
        slotExists(index1)
        slotExists(index2)
        syncPrevSums(index1.getParentIndex())
    {
        SlotStorage storage parent = slots[index1.getParentIndex()];
        SlotStorage storage slot1 = slots[index1];
        SlotStorage storage slot2 = slots[index2];
        uint256 available = getAvailable(index1.getParentIndex(), 0);
        bool isAllocated = slot1.prevSum.latest() < available;
        uint96 parentIndex = index1.getParentIndex();

        if (index1.getParentIndex() != index2.getParentIndex()) {
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
            childIndex = slots[parentIndex.createIndex(childIndex)].nextSlot
        ) {
            if (childIndex == index1.getChildIndex()) {
                revert WrongOrder();
            }
        }
        if (isAllocated && slot2.prevSum.latest() + slot2.size.latest() > available) {
            revert PartiallyAllocated();
        }

        if (index1.getChildIndex() == parent.firstChild) {
            parent.firstChild = index2.getChildIndex();
        }
        if (index2.getChildIndex() == parent.lastChild) {
            parent.lastChild = index1.getChildIndex();
            if (index2.getDepth() == 1) {
                _withdrawalBufferSlot().prevSlot = index1.getChildIndex();
            }
        }

        (slot1.nextSlot, slot2.nextSlot) = (slot2.nextSlot, slot1.nextSlot);
        if (slot1.nextSlot > 0) {
            slots[parentIndex.createIndex(slot1.nextSlot)].prevSlot = index1.getChildIndex();
        }
        slots[parentIndex.createIndex(slot2.nextSlot)].prevSlot = index2.getChildIndex();

        (slot1.prevSlot, slot2.prevSlot) = (slot2.prevSlot, slot1.prevSlot);
        slots[parentIndex.createIndex(slot1.prevSlot)].nextSlot = index1.getChildIndex();
        if (slot2.prevSlot > 0) {
            slots[parentIndex.createIndex(slot2.prevSlot)].nextSlot = index2.getChildIndex();
        }

        emit SwapSlots(index1, index2);
    }

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

    function _removeSlot(uint96 index) internal {
        SlotStorage storage slot = slots[index];
        SlotStorage storage parent = slots[index.getParentIndex()];

        if (index.getChildIndex() == parent.firstChild) {
            parent.firstChild = slot.nextSlot;
        } else {
            slots[index.getParentIndex().createIndex(slot.prevSlot)].nextSlot = slot.nextSlot;
        }
        if (index.getChildIndex() == parent.lastChild) {
            parent.lastChild = slot.prevSlot;
            slots[WITHDRAWAL_BUFFER_INDEX].prevSlot = slot.prevSlot;
        } else {
            slots[index.getParentIndex().createIndex(slot.nextSlot)].prevSlot = slot.prevSlot;
        }
        --parent.numChildren;
        slot.exists = false;

        emit RemoveSlot(index);
    }

    /* NETWORK FUNCTIONS */

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

            if (slots[index.getParentIndex()].numChildren == 1) {
                index = index.getParentIndex();
            }
            SlotStorage storage slot = slots[index];
            SlotStorage storage parent = slots[index.getParentIndex()];

            // clear pending for slot
            uint208 pending = getPending(index, 0);
            if (pending > 0) {
                parent.clearedChildrenPendingCumulative
                    .push(uint48(block.timestamp), parent.clearedChildrenPendingCumulative.latest() + pending);
            }
            // clear pending for plugins' utilization
            if (slot.noPlugins) {
                uint208 noPluginsPending = _getNoPluginsPending();
                if (noPluginsPending > 0) {
                    _clearedNoPluginsPendingCumulative.push(
                        uint48(block.timestamp), _clearedNoPluginsPendingCumulative.latest() + noPluginsPending
                    );
                }
            }
            // clear slot's size
            uint208 slotSize = slot.size.latest();
            if (slotSize > 0) {
                slot.size.push(uint48(block.timestamp), 0);
                parent.needPrevSumsSync = true;
                if (index.getDepth() == 1 && slot.noPlugins) {
                    _noPluginsSize -= slotSize;
                }
            }
            // remove slot to restrict from slashing
            _removeSlot(index);

            emit ResetAllocation(index, subnetwork);
        }
    }

    /* BASE DELEGATOR FUNCTIONS */

    /**
     * @inheritdoc IUniversalDelegator
     */
    function maxNetworkLimit(bytes32) public pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function setMaxNetworkLimit(uint96, uint256) public {}

    /**
     * @inheritdoc IUniversalDelegator
     */
    function setHook(address hook_) public nonReentrant onlyRole(HOOK_SET_ROLE) {
        if (hook == hook_) {
            revert AlreadySet();
        }

        hook = hook_;

        emit SetHook(hook_);
    }

    function onSlash(bytes32 subnetwork, address operator, uint256 amount, bytes memory data) public nonReentrant {
        unchecked {
            if (msg.sender != IVault(vault).slasher()) {
                revert NotSlasher();
            }

            // adjust slot's and its parents' allocations
            for (uint96 currentIndex = getSlotOf(subnetwork, operator); currentIndex > 0;) {
                SlotStorage storage slot = slots[currentIndex];
                uint208 pendingSlashed = uint208(Math.min(getPending(currentIndex, 0), amount));
                if (pendingSlashed > 0) {
                    slot.clearedPendingCumulative
                        .push(uint48(block.timestamp), slot.clearedPendingCumulative.latest() + pendingSlashed);
                    slots[currentIndex.getParentIndex()].clearedChildrenPendingCumulative
                        .push(
                            uint48(block.timestamp),
                            slots[currentIndex.getParentIndex()].clearedChildrenPendingCumulative.latest()
                                + pendingSlashed
                        );
                    if (currentIndex.getDepth() == 1 && slot.noPlugins) {
                        _clearedNoPluginsPendingCumulative.push(
                            uint48(block.timestamp), _clearedNoPluginsPendingCumulative.latest() + pendingSlashed
                        );
                    }
                }
                uint128 sizeSlashed = uint128(Math.min(slot.size.latest(), amount - pendingSlashed));
                if (sizeSlashed > 0) {
                    slot.size.push(uint48(block.timestamp), slot.size.latest() - sizeSlashed);
                    slots[currentIndex.getParentIndex()].needPrevSumsSync = true;
                    if (currentIndex.getDepth() == 1 && slot.noPlugins) {
                        _noPluginsSize -= sizeSlashed;
                    }
                }
                currentIndex = currentIndex.getParentIndex();
            }

            // make a call to the custom hook
            address hook_ = hook;
            if (hook_ != address(0)) {
                bytes memory calldata_ = abi.encodeCall(IDelegatorHook.onSlash, (subnetwork, operator, amount, data));

                if (gasleft() < HOOK_RESERVE + HOOK_GAS_LIMIT * 64 / 63) {
                    revert InsufficientHookGas();
                }

                assembly ("memory-safe") {
                    pop(call(HOOK_GAS_LIMIT, hook_, 0, add(calldata_, 0x20), mload(calldata_), 0, 0))
                }
            }

            emit OnSlash(subnetwork, operator, amount);
        }
    }

    function _initialize(bytes calldata data) internal override {
        (address vault_, bytes memory data_) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(vault_)) {
            revert NotVault();
        }

        if (IMigratableEntity(vault_).version() < 3) {
            revert OldVault();
        }

        InitParams memory params = abi.decode(data_, (InitParams));

        if (params.defaultAdminRoleHolder == address(0) && params.createSlotRoleHolder == address(0)) {
            revert MissingRoleHolders();
        }

        __ReentrancyGuard_init();

        vault = vault_;

        hook = params.hook;

        if (params.defaultAdminRoleHolder != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        }
        if (params.hookSetRoleHolder != address(0)) {
            _grantRole(HOOK_SET_ROLE, params.hookSetRoleHolder);
        }
        if (params.createSlotRoleHolder != address(0)) {
            _grantRole(CREATE_SLOT_ROLE, params.createSlotRoleHolder);
        }
        if (params.setSizeRoleHolder != address(0)) {
            _grantRole(SET_SIZE_ROLE, params.setSizeRoleHolder);
        }
        if (params.swapSlotsRoleHolder != address(0)) {
            _grantRole(SWAP_SLOTS_ROLE, params.swapSlotsRoleHolder);
        }

        _withdrawalBufferSlot().size.push(uint48(block.timestamp), type(uint128).max);

        emit Initialize(params);
    }

    function migrate() public {
        if (IMigratableEntity(vault).version() != 3) {
            revert WrongMigrate();
        }
        if (IEntity(IVaultV2(vault).delegator()).TYPE() == TYPE) {
            revert NotMigrating();
        }
        __migrateTimestamp = uint48(block.timestamp);
        __oldDelegator = IVaultV2(vault).delegator();

        _rootSlot().childrenPendingCumulative.push(uint48(block.timestamp), type(uint128).max);
        _noPluginsPendingCumulative.push(uint48(block.timestamp), type(uint128).max);
    }

    function _rootSlot() internal view returns (SlotStorage storage) {
        return slots[0];
    }

    function _withdrawalBufferSlot() internal view returns (SlotStorage storage) {
        return slots[WITHDRAWAL_BUFFER_INDEX];
    }
}

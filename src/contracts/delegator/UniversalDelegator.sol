// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {BaseDelegator} from "./BaseDelegator.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {UniversalDelegatorIndex} from "../libraries/UniversalDelegatorIndex.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {Multicallable as MulticallUpgradeable} from "@solady/src/utils/Multicallable.sol";

contract UniversalDelegator is BaseDelegator, MulticallUpgradeable, IUniversalDelegator {
    using UniversalDelegatorIndex for uint96;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    bytes32 public constant CREATE_SLOT_ROLE = keccak256("CREATE_SLOT_ROLE");
    bytes32 public constant SET_SIZE_ROLE = keccak256("SET_SIZE_ROLE");
    bytes32 public constant SWAP_SLOTS_ROLE = keccak256("SWAP_SLOTS_ROLE");
    bytes32 public constant REMOVE_SLOT_ROLE = keccak256("REMOVE_SLOT_ROLE");
    bytes32 public constant ASSIGN_NETWORK_ROLE = keccak256("ASSIGN_NETWORK_ROLE");
    bytes32 public constant UNASSIGN_NETWORK_ROLE = keccak256("UNASSIGN_NETWORK_ROLE");
    bytes32 public constant ASSIGN_OPERATOR_ROLE = keccak256("ASSIGN_OPERATOR_ROLE");
    bytes32 public constant UNASSIGN_OPERATOR_ROLE = keccak256("UNASSIGN_OPERATOR_ROLE");

    // @dev index is {32 bytes of child index at depth 1}{32 bytes - depth 2}{32 bytes - depth 3}
    mapping(uint96 index => SlotStorage slot) internal slots;
    mapping(bytes32 subnetwork => Checkpoints.Trace208) internal _networkToSlot;
    mapping(uint96 index => bytes32 subnetwork) internal _slotToNetwork;
    mapping(uint96 parentIndex => mapping(address operator => Checkpoints.Trace208)) internal _operatorToSlot;
    mapping(uint96 index => address operator) internal _slotToOperator;
    mapping(uint96 index => Checkpoints.Trace256 amount) internal _cumulativeSlash;

    modifier slotExists(uint96 index) {
        if (index > 0 && !slots[index].exists) {
            revert SlotNotCreated();
        }
        _;
    }

    constructor(
        address networkRegistry,
        address vaultFactory,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address delegatorFactory,
        uint64 entityType
    )
        BaseDelegator(
            networkRegistry,
            vaultFactory,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            delegatorFactory,
            entityType
        )
    {}

    /**
     * @inheritdoc IUniversalDelegator
     */
    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        return getAllocated(subnetwork, operator, duration);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getSlot(uint96 index) public view returns (Slot memory) {
        return Slot({
            exists: slots[index].exists,
            nextSlot: slots[index].nextSlot,
            prevSlot: slots[index].prevSlot,
            totalChildren: slots[index].totalChildren,
            firstChild: slots[index].firstChild,
            lastChild: slots[index].lastChild,
            isShared: slots[index].isShared,
            size: slots[index].size.latest(),
            prevSum: slots[index].prevSum.latest(),
            pendingFreeCumulative: slots[index].pendingFreeCumulative.latest()
        });
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev Returns the collateral balance of a given slot.
     */
    function getBalanceAt(uint96 index, uint48 timestamp, uint48 duration, bytes memory hints)
        public
        view
        returns (uint256)
    {
        if (index == 0) {
            if (timestamp != block.timestamp && duration != IVaultV2(vault).epochDuration()) {
                revert InvalidDuration();
            }
            return IVaultV2(vault).activeStakeAt(timestamp, hints) + IVaultV2(vault).activeWithdrawalsFor(duration);
        }
        return getAllocatedAt(index, timestamp, duration, hints);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getBalance(uint96 index, uint48 duration) public view returns (uint256) {
        if (index == 0) {
            return IVaultV2(vault).activeStake() + IVaultV2(vault).activeWithdrawalsFor(duration);
        }
        return getAllocated(index, duration);
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev Returns the available to allocate balance in the given slot.
     */
    function getAvailableAt(uint96 index, uint48 timestamp, uint48 duration, bytes memory hints)
        public
        view
        returns (uint256)
    {
        AvailableHints memory availableHints;
        if (hints.length > 0) {
            availableHints = abi.decode(hints, (AvailableHints));
        }
        return getBalanceAt(index, timestamp, duration, availableHints.balanceHints)
            .saturatingSub(
                slots[index].pendingFreeCumulative.upperLookupRecent(timestamp, availableHints.pendingFreeHint)
                    - slots[index].pendingFreeCumulative
                        .upperLookupRecent(
                            uint48(uint256(timestamp).saturatingSub(IVaultV2(vault).epochDuration())),
                            availableHints.pendingFreeEpochHint
                        )
            );
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAvailable(uint96 index, uint48 duration) public view returns (uint256) {
        return getBalance(index, duration)
            .saturatingSub(
                slots[index].pendingFreeCumulative.latest()
                    - slots[index].pendingFreeCumulative
                        .upperLookupRecent(uint48(block.timestamp.saturatingSub(IVaultV2(vault).epochDuration())))
            );
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev Returns the allocation of the given slot.
     */
    function getAllocatedAt(uint96 index, uint48 timestamp, uint48 duration, bytes memory hints)
        public
        view
        returns (uint256)
    {
        BaseAllocatedHints memory baseAllocatedHints;
        if (hints.length > 0) {
            baseAllocatedHints = abi.decode(hints, (BaseAllocatedHints));
        }
        uint256 available =
            getAvailableAt(index.getParentIndex(), timestamp, duration, baseAllocatedHints.availableHints);
        return Math.min(
            slots[index.getParentIndex()].isShared
                ? available
                : available.saturatingSub(
                    slots[index].prevSum.upperLookupRecent(timestamp, baseAllocatedHints.prevSumHint)
                ),
            slots[index].size.upperLookupRecent(timestamp, baseAllocatedHints.sizeHint)
        );
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAllocated(uint96 index, uint48 duration) public view returns (uint256) {
        uint256 available = getAvailable(index.getParentIndex(), duration);
        return Math.min(
            slots[index.getParentIndex()].isShared ? available : available.saturatingSub(slots[index].prevSum.latest()),
            slots[index].size.latest()
        );
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 timestamp, uint48 duration, bytes memory hints)
        public
        view
        returns (uint256)
    {
        AllocatedHints memory allocatedHints;
        if (hints.length > 0) {
            allocatedHints = abi.decode(hints, (AllocatedHints));
        }
        uint96 index = getSlotOfAt(subnetwork, operator, timestamp, allocatedHints.slotOfHints);
        return index > 0 ? getAllocatedAt(index, timestamp, duration, allocatedHints.allocatedHints) : 0;
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
    function getSlotOfNetworkAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (uint96) {
        return uint96(_networkToSlot[subnetwork].upperLookupRecent(timestamp, hint));
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
    function getSlotOfOperatorAt(uint96 parentIndex, address operator, uint48 timestamp, bytes memory hint)
        public
        view
        returns (uint96)
    {
        return uint96(_operatorToSlot[parentIndex][operator].upperLookupRecent(timestamp, hint));
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
    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        public
        view
        returns (uint96)
    {
        SlotOfHints memory slotOfHints;
        if (hints.length > 0) {
            slotOfHints = abi.decode(hints, (SlotOfHints));
        }
        return getSlotOfOperatorAt(
            getSlotOfNetworkAt(subnetwork, timestamp, slotOfHints.slotOfNetworkHints),
            operator,
            timestamp,
            slotOfHints.slotOfOperatorHints
        );
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
    function getIsShared(bytes32 subnetwork, address operator) public view returns (bool) {
        uint96 index = getSlotOf(subnetwork, operator);
        if (index == 0) {
            return false;
        }
        return slots[index.getParentIndex().getParentIndex()].isShared;
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function createSlot(uint96 parentIndex, bool isShared, uint256 size)
        public
        onlyRole(CREATE_SLOT_ROLE)
        slotExists(parentIndex)
    {
        if (isShared && parentIndex.getDepth() > 0) {
            revert WrongDepth();
        }
        SlotStorage storage parent = slots[parentIndex];
        uint32 childIndex = parent.totalChildren + 1;
        uint96 index = parentIndex.createIndex(childIndex);
        SlotStorage storage slot = slots[index];
        SlotStorage storage lastChild = slots[parentIndex.createIndex(parent.lastChild)];
        slot.exists = true;
        parent.totalChildren = childIndex;
        if (parent.firstChild == 0) {
            parent.firstChild = childIndex;
        } else {
            slot.prevSlot = parent.lastChild;
            lastChild.nextSlot = childIndex;
            slot.prevSum.push(uint48(block.timestamp), lastChild.prevSum.latest() + lastChild.size.latest());
        }
        parent.lastChild = childIndex;
        slot.isShared = isShared;
        slot.size.push(uint48(block.timestamp), size);

        emit CreateSlot(index, size);
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev if size increase: just change the size if slot not fully allocated or last child, otherwise use unallocated funds
     *      if size decrease: just change the size if slot not allocated, otherwise increase pending free
     */
    function setSize(uint96 index, uint256 size)
        public
        onlyRole(SET_SIZE_ROLE)
        slotExists(index)
        returns (uint256 pending)
    {
        SlotStorage storage slot = slots[index];
        uint256 currentSize = slot.size.latest();
        if (currentSize == size) {
            revert AlreadySet();
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        uint256 prevSum = slot.prevSum.latest();
        uint256 available = getAvailable(parentIndex, 0);
        if (size > currentSize) {
            if (!parent.isShared && prevSum + currentSize < available && slot.nextSlot > 0) {
                SlotStorage storage lastChild = slots[parentIndex.createIndex(parent.lastChild)];
                if (size - currentSize > available.saturatingSub(lastChild.prevSum.latest() + lastChild.size.latest()))
                {
                    revert NotEnoughAvailable();
                }
            }
        } else {
            if (!parent.isShared && prevSum < available) {
                pending = getAllocated(index, 0).saturatingSub(size);
                if (pending > 0) {
                    parent.pendingFreeCumulative
                        .push(uint48(block.timestamp), parent.pendingFreeCumulative.latest() + pending);
                }
            }
        }
        slot.size.push(uint48(block.timestamp), size);
        _syncPrevSums(parentIndex);

        emit SetSize(index, size);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function swapSlots(uint96 index1, uint96 index2)
        public
        onlyRole(SWAP_SLOTS_ROLE)
        slotExists(index1)
        slotExists(index2)
    {
        SlotStorage storage slot1 = slots[index1];
        SlotStorage storage slot2 = slots[index2];
        uint96 parentIndex = index1.getParentIndex();
        if (parentIndex != index2.getParentIndex()) {
            revert NotSameParent();
        }
        SlotStorage storage parent = slots[parentIndex];
        if (parent.isShared) {
            revert IsShared();
        }
        uint32 childIndex2 = index2.getChildIndex();
        for (uint32 childIndex = slot1.nextSlot; true;) {
            if (childIndex == childIndex2) {
                break;
            }
            childIndex = slots[parentIndex.createIndex(childIndex)].nextSlot;
            if (childIndex == 0) {
                revert WrongOrder();
            }
        }
        uint256 available = getAvailable(parentIndex, 0);
        bool isAllocated = slot1.prevSum.latest() < available;
        if (isAllocated != (slot2.prevSum.latest() < available)) {
            revert NotSameAllocated();
        }
        if (isAllocated && slot2.prevSum.latest() + slot2.size.latest() > available) {
            revert PartiallyAllocated();
        }
        (slot1.nextSlot, slot2.nextSlot) = (slot2.nextSlot, slot1.nextSlot);
        (slot1.prevSlot, slot2.prevSlot) = (slot2.prevSlot, slot1.prevSlot);

        _syncPrevSums(parentIndex);

        emit SwapSlots(index1, index2);
    }

    function removeSlot(uint96 index) public onlyRole(REMOVE_SLOT_ROLE) slotExists(index) {
        if (getAllocated(index, 0) > 0) {
            revert SlotAllocated();
        }

        bytes32 subnetwork = _slotToNetwork[index];
        if (subnetwork != bytes32(0)) {
            _networkToSlot[subnetwork].push(uint48(block.timestamp), 0);
        }

        SlotStorage storage slot = slots[index];
        uint32 childIndex = index.getChildIndex();
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        slot.exists = false;
        if (childIndex != parent.firstChild) {
            slots[parentIndex.createIndex(slot.prevSlot)].nextSlot = slot.nextSlot;
        }
        if (childIndex != parent.lastChild) {
            slots[parentIndex.createIndex(slot.nextSlot)].prevSlot = slot.prevSlot;
        }
        if (childIndex == parent.firstChild) {
            parent.firstChild = slot.nextSlot;
        }
        if (childIndex == parent.lastChild) {
            parent.lastChild = slot.prevSlot;
        }

        _syncPrevSums(parentIndex);

        emit RemoveSlot(index);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function assignNetwork(uint96 index, bytes32 subnetwork) public onlyRole(ASSIGN_NETWORK_ROLE) slotExists(index) {
        if (index.getDepth() != 2) {
            revert WrongDepth();
        }
        if (_slotToNetwork[index] != bytes32(0) || getSlotOfNetwork(subnetwork) > 0) {
            revert NetworkAlreadyAssigned();
        }
        _networkToSlot[subnetwork].push(uint48(block.timestamp), index);
        _slotToNetwork[index] = subnetwork;

        emit AssignNetwork(index, subnetwork);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function unassignNetwork(bytes32 subnetwork) public onlyRole(UNASSIGN_NETWORK_ROLE) {
        uint96 index = getSlotOfNetwork(subnetwork);
        if (index == 0) {
            revert NetworkNotAssigned();
        }
        if (getAllocated(index, 0) > 0) {
            revert SlotAllocated();
        }
        _networkToSlot[subnetwork].push(uint48(block.timestamp), 0);
        _slotToNetwork[index] = bytes32(0);

        emit UnassignNetwork(subnetwork);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function assignOperator(uint96 index, address operator) public onlyRole(ASSIGN_OPERATOR_ROLE) slotExists(index) {
        if (index.getDepth() != 3) {
            revert WrongDepth();
        }
        uint96 parentIndex = index.getParentIndex();
        if (_slotToOperator[index] != address(0) || getSlotOfOperator(parentIndex, operator) != 0) {
            revert OperatorAlreadyAssigned();
        }
        _operatorToSlot[parentIndex][operator].push(uint48(block.timestamp), index);
        _slotToOperator[index] = operator;

        emit AssignOperator(index, operator);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function unassignOperator(uint96 parentIndex, address operator) public onlyRole(UNASSIGN_OPERATOR_ROLE) {
        uint96 index = getSlotOfOperator(parentIndex, operator);
        if (index == 0) {
            revert OperatorNotAssigned();
        }
        if (getAllocated(index, 0) > 0) {
            revert SlotAllocated();
        }
        _operatorToSlot[parentIndex][operator].push(uint48(block.timestamp), 0);
        _slotToOperator[index] = address(0);

        emit UnassignOperator(index, operator);
    }

    function _syncPrevSums(uint96 parentIndex) internal {
        SlotStorage storage parent = slots[parentIndex];
        uint256 prevSum;
        for (uint32 childIndex = parent.firstChild; childIndex > 0;) {
            SlotStorage storage child = slots[parentIndex.createIndex(childIndex)];
            if (child.prevSum.latest() != prevSum) {
                child.prevSum.push(uint48(block.timestamp), prevSum);
            }
            prevSum += child.size.latest();
            childIndex = child.nextSlot;
        }
    }

    function _stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        internal
        view
        override
        returns (uint256, bytes memory)
    {
        StakeHints memory stakeHints;
        if (hints.length > 0) {
            stakeHints = abi.decode(hints, (StakeHints));
        }
        return (
            getAllocatedAt(subnetwork, operator, timestamp, type(uint48).max, stakeHints.allocatedHints),
            stakeHints.baseHints
        );
    }

    function _stake(bytes32 subnetwork, address operator) internal view override returns (uint256) {
        return getAllocated(subnetwork, operator, type(uint48).max);
    }

    function _setMaxNetworkLimit(bytes32, uint256) internal override {}

    function __initialize(address vault_, bytes memory data)
        internal
        override
        returns (IBaseDelegator.BaseParams memory)
    {
        if (IMigratableEntity(vault_).version() < 3) {
            revert OldVault();
        }

        InitParams memory params = abi.decode(data, (InitParams));

        if (params.baseParams.defaultAdminRoleHolder == address(0) && params.createSlotRoleHolder == address(0)) {
            revert MissingRoleHolders();
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
        if (params.assignNetworkRoleHolder != address(0)) {
            _grantRole(ASSIGN_NETWORK_ROLE, params.assignNetworkRoleHolder);
        }
        if (params.unassignNetworkRoleHolder != address(0)) {
            _grantRole(UNASSIGN_NETWORK_ROLE, params.unassignNetworkRoleHolder);
        }
        if (params.assignOperatorRoleHolder != address(0)) {
            _grantRole(ASSIGN_OPERATOR_ROLE, params.assignOperatorRoleHolder);
        }
        if (params.unassignOperatorRoleHolder != address(0)) {
            _grantRole(UNASSIGN_OPERATOR_ROLE, params.unassignOperatorRoleHolder);
        }

        return params.baseParams;
    }

    function migrate() public {
        if (IMigratableEntity(vault).version() != 3) {
            revert WrongMigrate();
        }
        address oldDelegator = IVaultV2(vault).delegator();
        uint64 oldDelegatorType = IEntity(oldDelegator).TYPE();
        if (oldDelegatorType == TYPE) {
            revert NotMigrating();
        }
        // TODO: replace type(uint128).max with ?
        slots[0].pendingFreeCumulative.push(uint48(block.timestamp), type(uint128).max);
    }
}

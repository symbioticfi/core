// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseDelegator} from "./BaseDelegator.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {UniversalDelegatorIndex} from "../libraries/UniversalDelegatorIndex.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

contract UniversalDelegator is BaseDelegator, MulticallUpgradeable, IUniversalDelegator {
    using UniversalDelegatorIndex for uint96;
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using Math for uint256;

    uint256 public constant MAX_SHARES = 1e27;
    bytes32 public constant CREATE_SLOT_ROLE = keccak256("CREATE_SLOT_ROLE");
    bytes32 public constant SET_IS_SHARED_ROLE = keccak256("SET_IS_SHARED_ROLE");
    bytes32 public constant SET_SIZE_ROLE = keccak256("SET_SIZE_ROLE");
    bytes32 public constant SET_SHARE_ROLE = keccak256("SET_SHARE_ROLE");
    bytes32 public constant SWAP_SLOTS_ROLE = keccak256("SWAP_SLOTS_ROLE");
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

    modifier slotCreated(uint96 index) {
        if (index > 0 && index.getChildIndex() > slots[index.getParentIndex()].children.length) {
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
    function getSlot(uint96 index) public view returns (Slot memory) {
        return Slot({
            children: slots[index].children,
            size: slots[index].size.latest(),
            share: slots[index].share.latest(),
            totalChildrenShares: slots[index].totalChildrenShares,
            prevSum: slots[index].prevSum.latest(),
            isShared: slots[index].isShared.latest(),
            totalChildrenSize: slots[index].totalChildrenSize.latest(),
            pendingFreeCumulative: slots[index].pendingFreeCumulative.latest()
        });
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev Returns the collateral balance of a given slot.
     */
    function getBalanceAt(uint96 index, uint48 timestamp, bytes memory hints) public view returns (uint256) {
        if (index == 0) {
            return IVault(vault).activeStakeAt(timestamp, hints);
        }
        return getAllocatedAt(index, timestamp, hints);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getBalance(uint96 index) public view returns (uint256) {
        if (index == 0) {
            return IVault(vault).activeStake();
        }
        return getAllocated(index);
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev Returns the available to allocate balance in the given slot.
     */
    function getAvailableAt(uint96 index, uint48 timestamp, bytes memory hints) public view returns (uint256) {
        AvailableHints memory availableHints;
        if (hints.length > 0) {
            availableHints = abi.decode(hints, (AvailableHints));
        }
        return getBalanceAt(index, timestamp, availableHints.balanceHints)
            .saturatingSub(
                slots[index].pendingFreeCumulative.upperLookupRecent(timestamp, availableHints.pendingFreeHint)
                    - slots[index].pendingFreeCumulative
                        .upperLookupRecent(
                            uint48(uint256(timestamp).saturatingSub(IVault(vault).epochDuration())),
                            availableHints.pendingFreeEpochHint
                        )
            );
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAvailable(uint96 index) public view returns (uint256) {
        return getBalance(index)
            .saturatingSub(
                slots[index].pendingFreeCumulative.latest()
                    - slots[index].pendingFreeCumulative
                        .upperLookupRecent(uint48(block.timestamp.saturatingSub(IVault(vault).epochDuration())))
            );
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev Returns the allocation of the given slot.
     */
    function getAllocatedAt(uint96 index, uint48 timestamp, bytes memory hints) public view returns (uint256) {
        BaseAllocatedHints memory baseAllocatedHints;
        if (hints.length > 0) {
            baseAllocatedHints = abi.decode(hints, (BaseAllocatedHints));
        }
        uint256 size = slots[index].size.upperLookupRecent(timestamp, baseAllocatedHints.sizeHint);
        uint256 unallocatedBySizes =
            _getParentUnallocatedBySizesAt(index, timestamp, baseAllocatedHints.unallocatedHints);
        if (unallocatedBySizes > 0) {
            return size
                + uint256(slots[index].share.upperLookupRecent(timestamp, baseAllocatedHints.shareOrAvailableHints))
                    .mulDiv(unallocatedBySizes, MAX_SHARES);
        }
        uint256 available = getAvailableAt(index.getParentIndex(), timestamp, baseAllocatedHints.shareOrAvailableHints);
        return Math.min(
            slots[index.getParentIndex()].isShared.upperLookupRecent(timestamp, baseAllocatedHints.isSharedHint) == 0
                ? available.saturatingSub(
                    slots[index].prevSum.upperLookupRecent(timestamp, baseAllocatedHints.prevSumHint)
                )
                : available,
            size
        );
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAllocated(uint96 index) public view returns (uint256) {
        uint256 size = slots[index].size.latest();
        uint256 unallocatedBySizes = _getParentUnallocatedBySizes(index);
        if (unallocatedBySizes > 0) {
            return size + uint256(slots[index].share.latest()).mulDiv(unallocatedBySizes, MAX_SHARES);
        }
        uint256 available = getAvailable(index.getParentIndex());
        return Math.min(
            slots[index.getParentIndex()].isShared.latest() == 0
                ? available.saturatingSub(slots[index].prevSum.latest())
                : available,
            size
        );
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        public
        view
        returns (uint256)
    {
        AllocatedHints memory allocatedHints;
        if (hints.length > 0) {
            allocatedHints = abi.decode(hints, (AllocatedHints));
        }
        uint96 index = getSlotOfAt(subnetwork, operator, timestamp, allocatedHints.slotOfHints);
        return index > 0 ? getAllocatedAt(index, timestamp, allocatedHints.allocatedHints) : 0;
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function getAllocated(bytes32 subnetwork, address operator) public view returns (uint256) {
        uint96 index = getSlotOf(subnetwork, operator);
        return index > 0 ? getAllocated(index) : 0;
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
    function isSharedAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        public
        view
        returns (bool)
    {
        IsSharedHints memory isSharedHints;
        if (hints.length > 0) {
            isSharedHints = abi.decode(hints, (IsSharedHints));
        }
        uint96 index = getSlotOfAt(subnetwork, operator, timestamp, isSharedHints.slotOfHints);
        if (index == 0) {
            return false;
        }
        return slots[index.getParentIndex().getParentIndex()].isShared
                .upperLookupRecent(timestamp, isSharedHints.isSharedHint) > 0;
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function isShared(bytes32 subnetwork, address operator) public view returns (bool) {
        uint96 index = getSlotOf(subnetwork, operator);
        if (index == 0) {
            return false;
        }
        return slots[index.getParentIndex().getParentIndex()].isShared.latest() > 0;
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function createSlot(uint96 parentIndex, bool isShared, uint256 size, uint208 share)
        public
        onlyRole(CREATE_SLOT_ROLE)
        slotCreated(parentIndex)
    {
        if (isShared && parentIndex.getDepth() > 0) {
            revert WrongDepth();
        }
        SlotStorage storage parent = slots[parentIndex];
        if (share > MAX_SHARES || (!isShared && parent.totalChildrenShares + share > MAX_SHARES)) {
            revert TooManyShares();
        }
        uint256 numChildren = parent.children.length;
        uint32 childIndex = uint32(numChildren) + 1;
        uint96 index = parentIndex.createIndex(childIndex);
        SlotStorage storage slot = slots[index];
        uint256 totalChildrenSize = parent.totalChildrenSize.latest();
        slot.prevSum.push(uint48(block.timestamp), totalChildrenSize);
        slot.isShared.push(uint48(block.timestamp), isShared ? 1 : 0);
        slot.size.push(uint48(block.timestamp), size);
        parent.totalChildrenSize.push(uint48(block.timestamp), totalChildrenSize + size);
        slot.share.push(uint48(block.timestamp), share);
        parent.totalChildrenShares += share;
        parent.children.push(childIndex);
        parent.childToLocalIndex[index] = uint32(numChildren);

        emit CreateSlot(index, size);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function setIsShared(uint96 index, bool isShared) public onlyRole(SET_IS_SHARED_ROLE) slotCreated(index) {
        if (index.getDepth() != 1) {
            revert WrongDepth();
        }
        SlotStorage storage slot = slots[index];
        if (slot.isShared.latest() == (isShared ? 1 : 0)) {
            revert IsSharedNotChanged();
        }
        if (getAllocated(index) > 0) {
            revert SlotAllocated();
        }
        if (!isShared && slot.totalChildrenShares > MAX_SHARES) {
            revert TooManyShares();
        }
        slot.isShared.push(uint48(block.timestamp), isShared ? 1 : 0);

        emit SetIsShared(index, isShared);
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev if size increase: just change the size if slot is shared or out of available liquidity, otherwise use unallocated funds with dependency of shares
     *      if size decrease: just change the size if slot is isolated and out of available liquidity, otherwise increase pending
     */
    function setSize(uint96 index, uint256 size)
        public
        onlyRole(SET_SIZE_ROLE)
        slotCreated(index)
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
        uint256 available = getAvailable(parentIndex);
        uint256 unallocatedBySizes = _getParentUnallocatedBySizes(index);
        if (size > currentSize) {
            if (parent.isShared.latest() == 0) {
                if (unallocatedBySizes == 0) {
                    if (
                        prevSum + currentSize < available
                            && parent.childToLocalIndex[index] < parent.children.length - 1
                    ) {
                        revert NotEnoughAvailable();
                    }
                } else {
                    // derive by knowing that "pending" must be accounted on size increase for neighbor slots with shares
                    // and "available" decrease by "pending" affects all slots
                    uint256 neighborShares = parent.totalChildrenShares - slot.share.latest();
                    if (neighborShares == MAX_SHARES) {
                        revert NotEnoughAvailable();
                    }
                    uint256 delta = size - currentSize;
                    pending = neighborShares.mulDiv(delta, MAX_SHARES - neighborShares, Math.Rounding.Ceil);
                    // TODO: also allow not just last child, but last child with size?
                    if (
                        parent.childToLocalIndex[index] < parent.children.length - 1
                            && delta > unallocatedBySizes.saturatingSub(pending)
                    ) {
                        revert NotEnoughAvailable();
                    }
                }
            }
        } else {
            // derive by knowing that "pending" must be accounted on size decrease for original slot
            // and, potentially, for neighbor slots with shares
            // and "available" decrease by "pending" affects all slots
            if (parent.isShared.latest() > 0) {
                pending = currentSize < available ? currentSize - size : available.saturatingSub(size);
            } else if (unallocatedBySizes > 0 || prevSum < available) {
                pending =
                    prevSum + currentSize < available ? currentSize - size : available.saturatingSub(prevSum + size);
            }
        }
        if (pending > 0) {
            parent.pendingFreeCumulative.push(uint48(block.timestamp), parent.pendingFreeCumulative.latest() + pending);
        }

        slot.size.push(uint48(block.timestamp), size);
        parent.totalChildrenSize.push(uint48(block.timestamp), parent.totalChildrenSize.latest() - currentSize + size);
        _syncPrevSums(index);

        emit SetSize(index, size);
    }

    /**
     * @inheritdoc IUniversalDelegator
     * @dev if share increase: just change the share if enough shares available for isolated slots, otherwise revert
     *      if share decrease: just change the share if no unallocated funds for sizes, otherwise increase pending
     */
    function setShare(uint96 index, uint208 share)
        public
        onlyRole(SET_SHARE_ROLE)
        slotCreated(index)
        returns (uint256 pending)
    {
        SlotStorage storage slot = slots[index];
        uint256 currentShare = slot.share.latest();
        if (currentShare == share) {
            revert AlreadySet();
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        if (share > currentShare) {
            if (
                share > MAX_SHARES
                    || (parent.isShared.latest() == 0 && parent.totalChildrenShares - currentShare + share > MAX_SHARES)
            ) {
                revert TooManyShares();
            }
        } else {
            uint256 unallocatedBySizes = _getParentUnallocatedBySizes(index);
            if (unallocatedBySizes > 0) {
                // derive by knowing that "pending" must be accounted on share decrease for original slot
                // and "available" decrease by "pending" affects all slots
                pending = unallocatedBySizes.mulDiv(currentShare - share, MAX_SHARES - share, Math.Rounding.Ceil);
            }
        }
        if (pending > 0) {
            parent.pendingFreeCumulative.push(uint48(block.timestamp), parent.pendingFreeCumulative.latest() + pending);
        }
        slot.share.push(uint48(block.timestamp), share);
        parent.totalChildrenShares = parent.totalChildrenShares - currentShare + share;

        emit SetShare(index, share);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function swapSlots(uint96 index1, uint96 index2)
        public
        onlyRole(SWAP_SLOTS_ROLE)
        slotCreated(index1)
        slotCreated(index2)
    {
        SlotStorage storage slot1 = slots[index1];
        SlotStorage storage slot2 = slots[index2];
        uint96 parentIndex = index1.getParentIndex();
        if (parentIndex != index2.getParentIndex()) {
            revert NotSameParent();
        }
        SlotStorage storage parent = slots[parentIndex];
        if (parent.isShared.latest() > 0) {
            revert IsShared();
        }
        (uint32 localIndex1, uint32 localIndex2) = (parent.childToLocalIndex[index1], parent.childToLocalIndex[index2]);
        if (localIndex1 >= localIndex2) {
            revert WrongOrder();
        }
        uint256 available = getAvailable(parentIndex);
        bool isAllocated = slot1.prevSum.latest() < available;
        if (isAllocated != (slot2.prevSum.latest() < available)) {
            revert NotSameAllocated();
        }
        if (isAllocated && slot2.prevSum.latest() + slot2.size.latest() > available) {
            revert PartiallyAllocated();
        }
        (parent.children[localIndex1], parent.children[localIndex2]) =
        (parent.children[localIndex2], parent.children[localIndex1]);
        (parent.childToLocalIndex[index1], parent.childToLocalIndex[index2]) = (localIndex2, localIndex1);

        slot2.prevSum.push(uint48(block.timestamp), slot1.prevSum.latest());
        _syncPrevSums(index2);

        emit SwapSlots(index1, index2);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function assignNetwork(uint96 index, bytes32 subnetwork) public onlyRole(ASSIGN_NETWORK_ROLE) slotCreated(index) {
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
        if (getAllocated(index) > 0) {
            revert SlotAllocated();
        }
        _networkToSlot[subnetwork].push(uint48(block.timestamp), 0);
        _slotToNetwork[index] = bytes32(0);

        emit UnassignNetwork(subnetwork);
    }

    /**
     * @inheritdoc IUniversalDelegator
     */
    function assignOperator(uint96 index, address operator) public onlyRole(ASSIGN_OPERATOR_ROLE) slotCreated(index) {
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
        if (getAllocated(index) > 0) {
            revert SlotAllocated();
        }
        _operatorToSlot[parentIndex][operator].push(uint48(block.timestamp), 0);
        _slotToOperator[index] = address(0);

        emit UnassignOperator(index, operator);
    }

    function _getParentUnallocatedBySizesAt(uint96 index, uint48 timestamp, bytes memory hints)
        internal
        view
        returns (uint256)
    {
        UnallocatedBySizesHints memory unallocatedBySizesHints;
        if (hints.length > 0) {
            unallocatedBySizesHints = abi.decode(hints, (UnallocatedBySizesHints));
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        return getAvailableAt(parentIndex, timestamp, unallocatedBySizesHints.availableHints)
            .saturatingSub(
                parent.isShared.upperLookupRecent(timestamp, unallocatedBySizesHints.isSharedHint) == 0
                    ? parent.totalChildrenSize
                        .upperLookupRecent(timestamp, unallocatedBySizesHints.totalChildrenSizeOrSizeHint)
                    : slots[index].size
                        .upperLookupRecent(timestamp, unallocatedBySizesHints.totalChildrenSizeOrSizeHint)
            );
    }

    function _getParentUnallocatedBySizes(uint96 index) internal view returns (uint256) {
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        return getAvailable(parentIndex)
            .saturatingSub(
                parent.isShared.latest() == 0 ? parent.totalChildrenSize.latest() : slots[index].size.latest()
            );
    }

    function _syncPrevSums(uint96 startIndex) internal {
        SlotStorage storage slot = slots[startIndex];
        uint96 parentIndex = startIndex.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        uint256 prevSum = slot.prevSum.latest() + slot.size.latest();
        uint256 numChildren = parent.children.length;
        for (uint32 i = parent.childToLocalIndex[startIndex] + 1; i < numChildren; ++i) {
            SlotStorage storage child = slots[parentIndex.createIndex(parent.children[i])];
            child.prevSum.push(uint48(block.timestamp), prevSum);
            prevSum += child.size.latest();
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
        return (getAllocatedAt(subnetwork, operator, timestamp, stakeHints.allocatedHints), stakeHints.baseHints);
    }

    function _stake(bytes32 subnetwork, address operator) internal view override returns (uint256) {
        return getAllocated(subnetwork, operator);
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
        if (params.setIsSharedRoleHolder != address(0)) {
            _grantRole(SET_IS_SHARED_ROLE, params.setIsSharedRoleHolder);
        }
        if (params.setSizeRoleHolder != address(0)) {
            _grantRole(SET_SIZE_ROLE, params.setSizeRoleHolder);
        }
        if (params.setShareRoleHolder != address(0)) {
            _grantRole(SET_SHARE_ROLE, params.setShareRoleHolder);
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
        // TODO: set type(uin256).max but also add "clearing" of matured pendings
        slots[0].pendingFreeCumulative.push(uint48(block.timestamp), type(uint256).max);
    }
}

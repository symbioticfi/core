// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseDelegator} from "./BaseDelegator.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {UniversalDelegatorIndex} from "../libraries/UniversalDelegatorIndex.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

contract UniversalDelegator is BaseDelegator, MulticallUpgradeable, IUniversalDelegator {
    using UniversalDelegatorIndex for uint96;
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using Math for uint256;

    struct Slot {
        uint32[] children;
        mapping(uint96 => uint32) childToLocalIndex;
        Checkpoints.Trace256 size;
        Checkpoints.Trace256 prevSum;
        Checkpoints.Trace208 isShared;
        Checkpoints.Trace256 pendingFreeCumulative;
    }

    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    // @dev index is {32 bytes of child index at depth 1}{32 bytes - depth 2}{32 bytes - depth 3}
    mapping(uint96 index => Slot slot) public slots;
    mapping(bytes32 subnetwork => Checkpoints.Trace208) internal _networkToSlot;
    mapping(uint96 parentIndex => mapping(address operator => Checkpoints.Trace208)) internal _operatorToSlot;
    mapping(uint96 index => address operator) public operatorBySlot;
    mapping(uint96 index => Checkpoints.Trace256 amount) internal _cumulativeSlash;

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

    // @dev Returns the collateral balance of a given slot.
    function getBalanceAt(uint96 index, uint48 timestamp, bytes memory hints) public view returns (uint256) {
        if (index == 0) {
            return IVault(vault).activeStakeAt(timestamp, hints);
        }
        return getAllocatedAt(index, timestamp, hints);
    }

    function getBalance(uint96 index) public view returns (uint256) {
        if (index == 0) {
            return IVault(vault).activeStake();
        }
        return getAllocated(index);
    }

    // @dev Returns the available to allocate balance in the given slot.
    function getAvailableAt(uint96 index, uint48 timestamp, bytes memory hints) public view returns (uint256) {
        return getBalanceAt(index, timestamp, hints)
            .saturatingSub(
                slots[index].pendingFreeCumulative.upperLookupRecent(timestamp, hints)
                    - slots[index].pendingFreeCumulative
                        .upperLookupRecent(
                            uint48(uint256(timestamp).saturatingSub(IVault(vault).epochDuration())), hints
                        )
            );
    }

    function getAvailable(uint96 index) public view returns (uint256) {
        return getBalance(index)
            .saturatingSub(
                slots[index].pendingFreeCumulative.latest()
                    - slots[index].pendingFreeCumulative
                        .upperLookupRecent(uint48(block.timestamp.saturatingSub(IVault(vault).epochDuration())))
            );
    }

    // @dev Returns the allocation of the given slot.
    function getAllocatedAt(uint96 index, uint48 timestamp, bytes memory hints) public view returns (uint256) {
        uint96 parentIndex = index.getParentIndex();
        Slot storage parent = slots[parentIndex];
        uint256 available = getAvailableAt(parentIndex, timestamp, hints);
        if (parent.isShared.upperLookupRecent(timestamp, hints) == 0) {
            available = available.saturatingSub(slots[index].prevSum.upperLookupRecent(timestamp, hints));
        }
        return Math.min(available, slots[index].size.upperLookupRecent(timestamp, hints));
    }

    function getAllocated(uint96 index) public view returns (uint256) {
        uint96 parentIndex = index.getParentIndex();
        Slot storage parent = slots[parentIndex];
        uint256 available = getAvailable(parentIndex);
        if (parent.isShared.latest() == 0) {
            available = available.saturatingSub(slots[index].prevSum.latest());
        }
        return Math.min(available, slots[index].size.latest());
    }

    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        public
        view
        returns (uint256)
    {
        uint96 index = slotOfAt(subnetwork, operator, timestamp, hints);
        return index > 0 ? getAllocatedAt(index, timestamp, hints) : 0;
    }

    function getAllocated(bytes32 subnetwork, address operator) public view returns (uint256) {
        uint96 index = slotOf(subnetwork, operator);
        return index > 0 ? getAllocated(index) : 0;
    }

    // @dev Returns the unallocated balance in the given slot (due to pendings or not fully allocated).
    function getUnallocated(uint96 index) public view returns (uint256) {
        return getAvailable(index).saturatingSub(_getChildrenSize(index));
    }

    function slotOfNetworkAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (uint96) {
        return uint96(_networkToSlot[subnetwork].upperLookupRecent(timestamp, hint));
    }

    function slotOfNetwork(bytes32 subnetwork) public view returns (uint96) {
        return uint96(_networkToSlot[subnetwork].latest());
    }

    function slotOfOperatorAt(uint96 parentIndex, address operator, uint48 timestamp, bytes memory hint)
        public
        view
        returns (uint96)
    {
        return uint96(_operatorToSlot[parentIndex][operator].upperLookupRecent(timestamp, hint));
    }

    function slotOfOperator(uint96 parentIndex, address operator) public view returns (uint96) {
        return uint96(_operatorToSlot[parentIndex][operator].latest());
    }

    function slotOfAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        public
        view
        returns (uint96)
    {
        return slotOfOperatorAt(slotOfNetworkAt(subnetwork, timestamp, hints), operator, timestamp, hints);
    }

    function slotOf(bytes32 subnetwork, address operator) public view returns (uint96) {
        return slotOfOperator(slotOfNetwork(subnetwork), operator);
    }

    function isRestakedAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        public
        view
        returns (bool)
    {
        uint96 index = slotOfAt(subnetwork, operator, timestamp, hints);
        if (index == 0) {
            return false;
        }
        for (index = index.getParentIndex(); index > 0; index = index.getParentIndex()) {
            if (slots[index].isShared.upperLookupRecent(timestamp, hints) > 0) {
                return true;
            }
        }
        return false;
    }

    function isRestaked(bytes32 subnetwork, address operator) public view returns (bool) {
        uint96 index = slotOf(subnetwork, operator);
        if (index == 0) {
            return false;
        }
        for (index = index.getParentIndex(); index > 0; index = index.getParentIndex()) {
            if (slots[index].isShared.latest() > 0) {
                return true;
            }
        }
        return false;
    }

    function createSlot(uint96 parentIndex, bool isShared, uint256 size) public onlyRole(CURATOR_ROLE) {
        if (isShared && parentIndex.getDepth() > 0) {
            revert WrongDepth();
        }
        uint256 numChildren = slots[parentIndex].children.length;
        uint32 childIndex = uint32(numChildren) + 1;
        uint96 index = parentIndex.createIndex(childIndex);
        Slot storage slot = slots[index];
        slot.prevSum.push(uint48(block.timestamp), _getChildrenSize(parentIndex));
        slot.isShared.push(uint48(block.timestamp), isShared ? 1 : 0);
        slot.size.push(uint48(block.timestamp), size);
        Slot storage parent = slots[parentIndex];
        parent.children.push(childIndex);
        parent.childToLocalIndex[index] = uint32(numChildren);

        emit CreateSlot(index, size);
    }

    function setIsShared(uint96 index, bool isShared) public onlyRole(CURATOR_ROLE) {
        if (index.getDepth() != 1) {
            revert WrongDepth();
        }
        Slot storage slot = slots[index];
        if (slot.isShared.latest() == (isShared ? 1 : 0)) {
            revert IsSharedNotChanged();
        }
        if (getAllocated(index) > 0) {
            revert SlotAllocated();
        }
        slot.isShared.push(uint48(block.timestamp), isShared ? 1 : 0);

        emit SetIsShared(index, isShared);
    }

    // @dev if size increase: just change the size if slot not fully allocated or last child, otherwise use unallocated funds
    // @dev if size decrease: just change the size if slot not allocated, otherwise increase pending free
    function setSize(uint96 index, uint256 size) public onlyRole(CURATOR_ROLE) {
        Slot storage slot = slots[index];
        uint96 parentIndex = index.getParentIndex();
        Slot storage parent = slots[parentIndex];
        if (size > slot.size.latest()) {
            if (
                parent.isShared.latest() == 0 && slot.prevSum.latest() + slot.size.latest() < getAvailable(parentIndex)
                    && parent.childToLocalIndex[index] < parent.children.length - 1
                    && size - slot.size.latest() > getUnallocated(parentIndex)
            ) {
                revert NotEnoughAvailable();
            }
        } else {
            if (getAllocated(index) > size) {
                parent.pendingFreeCumulative
                    .push(uint48(block.timestamp), getAllocated(index) - size + parent.pendingFreeCumulative.latest());
            }
        }
        slot.size.push(uint48(block.timestamp), size);

        _syncPrevSums(index);

        emit SetSize(index, size);
    }

    function swapSlots(uint96 index1, uint96 index2) public onlyRole(CURATOR_ROLE) {
        Slot storage slot1 = slots[index1];
        Slot storage slot2 = slots[index2];
        uint96 parentIndex = index1.getParentIndex();
        if (parentIndex != index2.getParentIndex()) {
            revert NotSameParent();
        }
        Slot storage parent = slots[parentIndex];
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

    function assignNetwork(uint96 index, bytes32 subnetwork) public onlyRole(CURATOR_ROLE) {
        if (index.getDepth() != 2) {
            revert WrongDepth();
        }
        if (slotOfNetwork(subnetwork) > 0) {
            revert NetworkAlreadyAssigned();
        }
        _networkToSlot[subnetwork].push(uint48(block.timestamp), index);

        emit AssignNetwork(index, subnetwork);
    }

    function unassignNetwork(bytes32 subnetwork) public onlyRole(CURATOR_ROLE) {
        uint96 index = slotOfNetwork(subnetwork);
        if (index == 0) {
            revert NetworkNotAssigned();
        }
        if (getAllocated(index) > 0) {
            revert SlotAllocated();
        }
        _networkToSlot[subnetwork].push(uint48(block.timestamp), 0);

        emit UnassignNetwork(subnetwork);
    }

    function assignOperator(uint96 index, address operator) public onlyRole(CURATOR_ROLE) {
        if (index.getDepth() != 3) {
            revert WrongDepth();
        }
        uint96 parentIndex = index.getParentIndex();
        if (slotOfOperator(parentIndex, operator) != 0) {
            revert OperatorAlreadyAssigned();
        }
        _operatorToSlot[parentIndex][operator].push(uint48(block.timestamp), index);
        operatorBySlot[index] = operator;

        emit AssignOperator(index, operator);
    }

    function unassignOperator(uint96 parentIndex, address operator) public onlyRole(CURATOR_ROLE) {
        uint96 index = slotOfOperator(parentIndex, operator);
        if (index == 0) {
            revert OperatorNotAssigned();
        }
        if (getAllocated(index) > 0) {
            revert SlotAllocated();
        }
        _operatorToSlot[parentIndex][operator].push(uint48(block.timestamp), 0);
        delete operatorBySlot[index];

        emit UnassignOperator(index, operator);
    }

    function _getChildrenSize(uint96 index) internal view returns (uint256) {
        uint256 numChildren = slots[index].children.length;
        if (numChildren == 0) {
            return 0;
        }
        Slot storage child = slots[index.createIndex(slots[index].children[numChildren - 1])];
        return child.prevSum.latest() + child.size.latest();
    }

    function _syncPrevSums(uint96 startIndex) internal {
        Slot storage slot = slots[startIndex];
        uint96 parentIndex = startIndex.getParentIndex();
        Slot storage parent = slots[parentIndex];
        uint256 prevSum = slot.prevSum.latest() + slot.size.latest();
        uint256 numChildren = parent.children.length;
        for (uint32 i = parent.childToLocalIndex[startIndex] + 1; i < numChildren; ++i) {
            Slot storage child = slots[parentIndex.createIndex(parent.children[i])];
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
        StakeHints memory stakesHints;
        if (hints.length > 0) {
            stakesHints = abi.decode(hints, (StakeHints));
        }
        return (getAllocatedAt(subnetwork, operator, timestamp, stakesHints.allocatedHints), stakesHints.baseHints);
    }

    function _stake(bytes32 subnetwork, address operator) internal view override returns (uint256) {
        return getAllocated(subnetwork, operator);
    }

    function _setMaxNetworkLimit(bytes32 subnetwork, uint256 amount) internal override {}

    function _onSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory /*data*/
    )
        internal
        override
    {
        uint96 groupIndex =
            slotOfAt(subnetwork, operator, captureTimestamp, new bytes(0)).getParentIndex().getParentIndex();

        uint256 latestCumulativeSlash = _cumulativeSlash[groupIndex].latest();
        if (
            amount
                > getAllocatedAt(groupIndex, captureTimestamp, new bytes(0))
                    .saturatingSub(
                        latestCumulativeSlash - _cumulativeSlash[groupIndex].upperLookupRecent(captureTimestamp)
                    )
        ) {
            revert();
        }

        _cumulativeSlash[groupIndex].push(uint48(block.timestamp), latestCumulativeSlash + amount);
    }

    function __initialize(address, bytes memory data) internal override returns (IBaseDelegator.BaseParams memory) {
        InitParams memory params = abi.decode(data, (InitParams));

        if (params.baseParams.defaultAdminRoleHolder == address(0) && params.curatorRoleHolder == address(0)) {
            revert MissingRoleHolders();
        }

        _grantRole(CURATOR_ROLE, params.curatorRoleHolder);

        return params.baseParams;
    }
}

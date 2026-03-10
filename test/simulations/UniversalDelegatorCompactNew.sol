// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Entity} from "../../src/contracts/common/Entity.sol";

import {Checkpoints} from "../../src/contracts/libraries/CheckpointsV2.sol";
import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";

import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IRegistry} from "../../src/interfaces/common/IRegistry.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../src/interfaces/vault/IVaultV2.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";

/// @title UniversalDelegatorCompactNew
/// @notice Compact delegator simulation with root -> subvault -> network -> operator support.
contract UniversalDelegatorCompactNew is Entity, AccessControlUpgradeable {
    using Math for uint256;
    using UniversalDelegatorIndex for uint96;
    using Checkpoints for Checkpoints.Trace208;

    /* ERRORS */

    error NotVault();
    error OldVault();
    error NotAssigned();
    error NotSlasher();
    error AlreadyAssigned();
    error NotEnoughAvailable();
    error SlotNotCreated();
    error TooManyChildren();
    error WrongDepth();

    /* STRUCTS */

    struct InitParams {
        address defaultAdminRoleHolder;
        address createSlotRoleHolder;
        address setSizeRoleHolder;
    }

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
        Checkpoints.Trace208 pendingCumulative;
        Checkpoints.Trace208 clearedPendingCursor;
        Checkpoints.Trace208 sizeSlashedPendingCumulative;
        Checkpoints.Trace208 sharedPendingClearedCursor;
    }

    struct Slot {
        bool exists;
        bool isShared;
        bool noPlugins;
        uint32 prevSlot;
        uint32 totalChildren;
        uint32 existChildren;
        uint32 nextSlot;
        uint32 lastChild;
        uint32 firstChild;
        uint128 size;
        uint208 prevSum;
        uint208 sizeSlashedPendingCumulative;
        bytes32 subnetworkOrOperator;
    }

    /* CONSTANTS */

    uint256 internal constant MAX_SLOTS = 10;

    // Keccak256("CREATE_SLOT_ROLE").
    bytes32 public constant CREATE_SLOT_ROLE = keccak256("CREATE_SLOT_ROLE");
    // Keccak256("SET_SIZE_ROLE").
    bytes32 public constant SET_SIZE_ROLE = keccak256("SET_SIZE_ROLE");

    /* IMMUTABLES */

    address internal immutable VAULT_FACTORY;

    /* STATE VARIABLES */

    /// @notice Connected vault.
    address public vault;

    /// @dev Slot storage keyed by encoded slot index.
    mapping(uint96 index => SlotStorage slot) internal slots;
    /// @dev Mapping from subnetwork id to network slot index checkpoints.
    mapping(bytes32 subnetwork => Checkpoints.Trace208) internal _networkToSlot;
    /// @dev Mapping from slot index to subnetwork id.
    mapping(uint96 index => bytes32 subnetwork) internal _slotToNetwork;
    /// @dev Mapping from parent slot and operator to slot index checkpoints.
    mapping(uint96 parentIndex => mapping(address operator => Checkpoints.Trace208)) internal _operatorToSlot;
    /// @dev Mapping from slot index to operator address.
    mapping(uint96 index => address operator) internal _slotToOperator;

    /* MODIFIERS */

    modifier slotExists(uint96 index) {
        if (index > 0 && !slots[index].exists) {
            revert SlotNotCreated();
        }
        _;
    }

    /* EVENTS */

    event Initialize(InitParams params);
    event CreateSlot(uint96 indexed index, bool isShared, bool noPlugins, uint128 size);
    event SetSize(uint96 indexed index, uint128 size);
    event SwapSlots(uint96 indexed index1, uint96 indexed index2);
    event OnSlash(bytes32 indexed subnetwork, address indexed operator, uint256 amount);

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address delegatorFactory, uint64 entityType)
        Entity(delegatorFactory, entityType)
    {
        VAULT_FACTORY = vaultFactory;
    }

    function VERSION() public pure returns (uint64) {
        return 1;
    }

    /* VIEW FUNCTIONS */

    function stakeForAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        public
        view
        returns (uint256)
    {
        return getAllocatedAt(subnetwork, operator, duration, timestamp);
    }

    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        return getAllocated(subnetwork, operator, duration);
    }

    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory)
        public
        view
        returns (uint256)
    {
        return getAllocatedAt(subnetwork, operator, IVaultV2(vault).epochDuration() - 1, timestamp);
    }

    function stake(bytes32 subnetwork, address operator) public view returns (uint256) {
        return getAllocated(subnetwork, operator, IVaultV2(vault).epochDuration() - 1);
    }

    function getSlotOfNetworkAt(bytes32 subnetwork, uint48 timestamp) public view returns (uint96) {
        return uint96(_networkToSlot[subnetwork].upperLookupRecent(timestamp));
    }

    function getSlotOfNetwork(bytes32 subnetwork) public view returns (uint96) {
        return uint96(_networkToSlot[subnetwork].latest());
    }

    function getSlotOfOperatorAt(uint96 parentIndex, address operator, uint48 timestamp) public view returns (uint96) {
        return uint96(_operatorToSlot[parentIndex][operator].upperLookupRecent(timestamp));
    }

    function getSlotOfOperator(uint96 parentIndex, address operator) public view returns (uint96) {
        return uint96(_operatorToSlot[parentIndex][operator].latest());
    }

    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp) public view returns (uint96) {
        uint96 networkIndex = getSlotOfNetworkAt(subnetwork, timestamp);
        return networkIndex > 0 ? getSlotOfOperatorAt(networkIndex, operator, timestamp) : 0;
    }

    function getSlotOf(bytes32 subnetwork, address operator) public view returns (uint96) {
        uint96 networkIndex = getSlotOfNetwork(subnetwork);
        return networkIndex > 0 ? getSlotOfOperator(networkIndex, operator) : 0;
    }

    function getSlot(uint96 index) public view returns (Slot memory) {
        return Slot({
            exists: slots[index].exists,
            isShared: slots[index].isShared,
            noPlugins: slots[index].noPlugins,
            prevSlot: slots[index].prevSlot,
            totalChildren: slots[index].totalChildren,
            existChildren: slots[index].existChildren,
            nextSlot: uint32(slots[index].nextSlot.latest()),
            lastChild: uint32(slots[index].lastChild.latest()),
            firstChild: uint32(slots[index].firstChild.latest()),
            size: uint128(slots[index].size.latest()),
            prevSum: _getPrevSum(index, 0),
            sizeSlashedPendingCumulative: slots[index].sizeSlashedPendingCumulative.latest(),
            subnetworkOrOperator: index.getDepth() == 3
                ? bytes32(bytes20(_slotToOperator[index]))
                : index.getDepth() == 2 ? _slotToNetwork[index] : bytes32(0)
        });
    }

    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        public
        view
        returns (uint256)
    {
        uint96 index = getSlotOfAt(subnetwork, operator, timestamp);
        return index > 0 ? getAllocatedAt(index, duration, timestamp) : 0;
    }

    function getAllocated(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        uint96 index = getSlotOf(subnetwork, operator);
        return index > 0 ? getAllocated(index, duration) : 0;
    }

    function getIsNoPlugins(bytes32) public pure returns (bool) {
        return true;
    }

    function getPendingAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint208) {
        unchecked {
            SlotStorage storage slot = slots[index];
            uint48 fromTimestamp = uint48(
                uint256(timestamp).saturatingSub(uint256(IVaultV2(vault).epochDuration()).saturatingSub(duration))
            );
            return slot.pendingCumulative.upperLookupRecent(timestamp)
                - uint208(
                Math.max(
                slot.clearedPendingCursor.upperLookupRecent(timestamp),
                slot.pendingCumulative.upperLookupRecent(fromTimestamp)
            )
            );
        }
    }

    function getPending(uint96 index, uint48 duration) public view returns (uint208) {
        unchecked {
            SlotStorage storage slot = slots[index];
            uint48 fromTimestamp =
                uint48(block.timestamp.saturatingSub(uint256(IVaultV2(vault).epochDuration()).saturatingSub(duration)));
            return slot.pendingCumulative.latest()
                - uint208(
                Math.max(slot.clearedPendingCursor.latest(), slot.pendingCumulative.upperLookupRecent(fromTimestamp))
            );
        }
    }

    function getBalanceAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        unchecked {
            return index > 0
                ? getAllocatedAt(index, duration, timestamp)
                : IVaultV2(vault).activeStakeAt(timestamp, "")
                    + IVaultV2(vault).activeWithdrawalsForAt(duration, timestamp);
        }
    }

    function getBalance(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            return index > 0
                ? getAllocated(index, duration)
                : IVaultV2(vault).activeStake() + IVaultV2(vault).activeWithdrawalsFor(duration);
        }
    }

    function getAllocatedAt(uint96 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        unchecked {
            if (duration >= IVaultV2(vault).epochDuration()) {
                return 0;
            }

            uint96 parentIndex = index.getParentIndex();
            SlotStorage storage parent = slots[parentIndex];
            uint256 slotAvailable = getBalanceAt(parentIndex, duration, timestamp);
            if (parentIndex.getDepth() != 1 || !parent.isShared) {
                slotAvailable = slotAvailable.saturatingSub(_getPrevSumAt(index, 0, timestamp));
            }
            return Math.min(
                slotAvailable, slots[index].size.upperLookupRecent(timestamp) + getPendingAt(index, duration, timestamp)
            );
        }
    }

    function getAllocated(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            if (duration >= IVaultV2(vault).epochDuration()) {
                return 0;
            }

            uint96 parentIndex = index.getParentIndex();
            SlotStorage storage parent = slots[parentIndex];
            uint256 slotAvailable = getBalance(parentIndex, duration);
            if (parentIndex.getDepth() != 1 || !parent.isShared) {
                slotAvailable = slotAvailable.saturatingSub(_getPrevSum(index, 0));
            } else if (IVaultV2(vault).slasher() == msg.sender) {
                // duration is ignored as UniversalDelegator uses only stakeFor(0)
                slotAvailable += _getSharedPendingAddBack(parentIndex, index, duration);
                slotAvailable += uint256(_getSlashPending(parentIndex)).saturatingSub(_getSlashPending(index));
            }
            return Math.min(slotAvailable, slots[index].size.latest() + getPending(index, duration));
        }
    }

    /* PUBLIC FUNCTIONS */

    function createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noPlugins, uint128 size)
        public
        onlyRole(CREATE_SLOT_ROLE)
        returns (uint96 index)
    {
        return _createSlot(subnetworkOrOperator, parentIndex, isShared, noPlugins, size);
    }

    function onSlash(bytes32 subnetwork, address operator, uint256 amount, bytes memory data)
        public
        returns (uint256 slashed)
    {
        unchecked {
            data;
            if (IVaultV2(vault).slasher() != msg.sender) {
                revert NotSlasher();
            }

            slashed = amount;
            uint96 index = getSlotOf(subnetwork, operator);
            for (uint96 curIndex = index; curIndex > 0;) {
                SlotStorage storage slot = slots[curIndex];

                uint208 pendingSlashed = uint208(Math.min(getPending(curIndex, 0), amount));
                if (pendingSlashed > 0) {
                    slot.clearedPendingCursor
                        .push(
                            uint48(block.timestamp),
                            _getPendingCursor(slot.pendingCumulative, slot.clearedPendingCursor) + pendingSlashed
                        );
                }

                uint128 sizeSlashed = uint128(Math.min(slot.size.latest(), amount - pendingSlashed));
                if (sizeSlashed > 0) {
                    slot.size.push(uint48(block.timestamp), slot.size.latest() - sizeSlashed);
                }

                if (curIndex.getDepth() == 1 && slot.isShared) {
                    slashed = pendingSlashed + sizeSlashed;

                    if (pendingSlashed > 0) {
                        uint96 networkIndex = index.getParentIndex();
                        slots[networkIndex].sharedPendingClearedCursor.push(
                            uint48(block.timestamp),
                            _getPendingCursor(slot.pendingCumulative, slots[networkIndex].sharedPendingClearedCursor)
                                + pendingSlashed
                        );
                    }
                    if (sizeSlashed > 0) {
                        slot.sizeSlashedPendingCumulative
                            .push(uint48(block.timestamp), slot.sizeSlashedPendingCumulative.latest() + sizeSlashed);
                        slots[index.getParentIndex()].sizeSlashedPendingCumulative
                            .push(
                                uint48(block.timestamp),
                                slots[index.getParentIndex()].sizeSlashedPendingCumulative.latest() + sizeSlashed
                            );
                    }
                }

                curIndex = curIndex.getParentIndex();
            }

            emit OnSlash(subnetwork, operator, amount);
        }
    }

    /// @dev Create a new slot.
    function _createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noPlugins, uint128 size)
        internal
        slotExists(parentIndex)
        returns (uint96 index)
    {
        unchecked {
            address operator;
            if (uint256(subnetworkOrOperator) <= type(uint160).max) {
                operator = address(uint160(uint256(subnetworkOrOperator)));
            }
            if (parentIndex.getDepth() > 2) {
                revert WrongDepth();
            }
            if (parentIndex.getDepth() > 0 && (isShared || noPlugins)) {
                revert WrongDepth();
            }

            SlotStorage storage parent = slots[parentIndex];
            if (++parent.existChildren > MAX_SLOTS) {
                revert TooManyChildren();
            }
            ++parent.totalChildren;

            index = parentIndex.createIndex(parent.totalChildren);

            SlotStorage storage slot = slots[index];
            slot.exists = true;
            slot.isShared = isShared;
            slot.noPlugins = noPlugins;

            if (parentIndex.getDepth() == 1) {
                if (_networkToSlot[subnetworkOrOperator].latest() > 0) {
                    revert AlreadyAssigned();
                }
                _networkToSlot[subnetworkOrOperator].push(uint48(block.timestamp), index);
                _slotToNetwork[index] = subnetworkOrOperator;
            } else if (operator != address(0) && parentIndex.getDepth() == 2) {
                if (_operatorToSlot[parentIndex][operator].latest() > 0) {
                    revert AlreadyAssigned();
                }
                _operatorToSlot[parentIndex][operator].push(uint48(block.timestamp), index);
                _slotToOperator[index] = operator;
            }

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

            emit CreateSlot(index, isShared, noPlugins, size);
        }
    }

    function setSize(uint96 index, uint128 newSize) public onlyRole(SET_SIZE_ROLE) slotExists(index) {
        unchecked {
            SlotStorage storage slot = slots[index];
            SlotStorage storage parent = slots[index.getParentIndex()];
            uint128 curSize = uint128(slot.size.latest());
            if (curSize == newSize) {
                return;
            }

            if (newSize > curSize) {
                uint48 maxDuration = IVaultV2(vault).epochDuration() - 1;
                uint256 curBalance = getBalance(index.getParentIndex(), 0);
                uint256 minBalance = getBalance(index.getParentIndex(), maxDuration);
                if (!parent.isShared && _getPrevSum(index, maxDuration) < curBalance && slot.nextSlot.latest() > 0) {
                    uint96 lastIndex = index.getParentIndex().createIndex(uint32(parent.lastChild.latest()));
                    if (
                        newSize - curSize
                            > minBalance.saturatingSub(
                                _getPrevSum(lastIndex, 0) + slots[lastIndex].size.latest() + getPending(lastIndex, 0)
                            )
                    ) {
                        revert NotEnoughAvailable();
                    }
                }
            } else {
                uint208 addPending =
                    uint208(getAllocated(index, 0).saturatingSub(getPending(index, 0)).saturatingSub(newSize));
                if (addPending > 0) {
                    slot.pendingCumulative.push(uint48(block.timestamp), slot.pendingCumulative.latest() + addPending);
                }
            }

            slot.size.push(uint48(block.timestamp), newSize);
            emit SetSize(index, newSize);
        }
    }

    function swapSlots(uint96 index1, uint96 index2) public slotExists(index1) slotExists(index2) {
        unchecked {
            uint96 parentIndex = index1.getParentIndex();
            SlotStorage storage parent = slots[parentIndex];
            SlotStorage storage slot1 = slots[index1];
            SlotStorage storage slot2 = slots[index2];

            if (parentIndex != index2.getParentIndex()) {
                revert();
            }
            if (parent.isShared) {
                revert();
            }
            for (
                uint32 childIndex = index2.getChildIndex();
                childIndex > 0;
                childIndex = uint32(slots[parentIndex.createIndex(childIndex)].nextSlot.latest())
            ) {
                if (childIndex == index1.getChildIndex()) {
                    revert();
                }
            }

            {
                uint48 maxDuration = IVaultV2(vault).epochDuration() - 1;
                uint256 balanceMaxDuration = getBalance(parentIndex, maxDuration);
                uint256 curPrevSum = _getPrevSum(index2, 0);
                if (curPrevSum < balanceMaxDuration) {
                    if (curPrevSum + slots[index2].size.latest() + getPending(index2, 0) > balanceMaxDuration) {
                        revert();
                    }
                } else if (_getPrevSum(index1, maxDuration) < getBalance(parentIndex, 0)) {
                    revert();
                }
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

    /* INITIALIZATION */

    function _initialize(bytes calldata data) internal override {
        (address initVault, bytes memory initData) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(initVault)) {
            revert NotVault();
        }

        if (IMigratableEntity(initVault).version() < VAULT_V2_VERSION) {
            revert OldVault();
        }

        InitParams memory params = abi.decode(initData, (InitParams));

        vault = initVault;

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(CREATE_SLOT_ROLE, params.createSlotRoleHolder);
        _grantRoleIfNotZero(SET_SIZE_ROLE, params.setSizeRoleHolder);

        emit Initialize(params);
    }

    /* UTILITY FUNCTIONS */

    function _getPendingCursor(
        Checkpoints.Trace208 storage pendingCumulative,
        Checkpoints.Trace208 storage clearedCursor
    ) internal view returns (uint208) {
        return uint208(
            Math.max(
                clearedCursor.latest(),
                pendingCumulative.upperLookupRecent(
                    uint48(block.timestamp.saturatingSub(IVaultV2(vault).epochDuration()))
                )
            )
        );
    }

    function _getPrevSumAt(uint96 index, uint48 duration, uint48 timestamp) internal view returns (uint208 prevSum) {
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
            SlotStorage storage child = slots[curIndex];
            prevSum += child.size.upperLookupRecent(timestamp) + getPendingAt(curIndex, duration, timestamp);
            childIndex = uint32(child.nextSlot.upperLookupRecent(timestamp));
        }
    }

    function _getSlashPending(uint96 index) internal view returns (uint208) {
        unchecked {
            SlotStorage storage slot = slots[index];
            if (slot.sizeSlashedPendingCumulative.length() == 0) {
                return 0;
            }

            uint48 fromTimestamp = uint48(block.timestamp.saturatingSub(uint256(IVaultV2(vault).epochDuration())));
            (, uint48 lastSlashKey, uint208 slashPendingCumulativeLatest) =
                slot.sizeSlashedPendingCumulative.latestCheckpoint();
            if (lastSlashKey < fromTimestamp) {
                return 0;
            }

            if (fromTimestamp == 0) {
                return slashPendingCumulativeLatest;
            }

            return slashPendingCumulativeLatest
                - slot.sizeSlashedPendingCumulative.upperLookupRecent(uint48(uint256(fromTimestamp) - 1));
        }
    }

    function _getSharedPendingAddBack(uint96 sharedIndex, uint96 networkIndex, uint48 duration)
        internal
        view
        returns (uint256)
    {
        unchecked {
            uint48 fromTimestamp =
                uint48(block.timestamp.saturatingSub(uint256(IVaultV2(vault).epochDuration()).saturatingSub(duration)));
            uint208 pendingFloor = slots[sharedIndex].pendingCumulative.upperLookupRecent(fromTimestamp);
            uint208 clearedAll = slots[sharedIndex].clearedPendingCursor.latest();
            uint208 clearedByNetwork =
                uint208(Math.max(slots[networkIndex].sharedPendingClearedCursor.latest(), pendingFloor));

            return uint256(Math.max(clearedAll, pendingFloor)).saturatingSub(clearedByNetwork);
        }
    }

    function _getPrevSum(uint96 index, uint48 duration) internal view returns (uint208 prevSum) {
        if (index == 0) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
        if (parentIndex.getDepth() == 1 && parent.isShared) {
            return 0;
        }
        for (uint32 childIndex = uint32(parent.firstChild.latest()); childIndex > 0;) {
            uint96 curIndex = parentIndex.createIndex(childIndex);
            if (index == curIndex) {
                break;
            }
            SlotStorage storage child = slots[curIndex];
            prevSum += child.size.latest() + getPending(curIndex, duration);
            childIndex = uint32(child.nextSlot.latest());
        }
    }

    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}

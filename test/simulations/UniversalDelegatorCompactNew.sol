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
/// @notice Compact delegator with a single (root -> slots) depth and isolated allocation only.
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

    /// @dev Slot storage keyed by encoded slot index (depth 1 only).
    mapping(uint96 index => SlotStorage slot) internal slots;
    /// @dev Mapping from operator to slot index (depth 1 only).
    mapping(address operator => uint96 index) internal _operatorToSlot;
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

    function getSlotOf(bytes32, address operator) public view returns (uint96) {
        return _operatorToSlot[operator];
    }

    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        public
        view
        returns (uint256)
    {
        uint96 index = getSlotOf(subnetwork, operator);
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

            uint256 aggregated = _getAggregatedAt(index, duration, timestamp);
            return duration == 0 ? aggregated : Math.min(aggregated, _getAggregatedAt(index, 0, timestamp));
        }
    }

    function getAllocated(uint96 index, uint48 duration) public view returns (uint256) {
        unchecked {
            if (duration >= IVaultV2(vault).epochDuration()) {
                return 0;
            }

            uint256 aggregated = _getAggregated(index, duration);
            return duration == 0 ? aggregated : Math.min(aggregated, _getAggregated(index, 0));
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

    function onSlash(bytes32 subnetwork, address operator, uint256 amount, bytes memory data) public {
        unchecked {
            data;
            if (IVaultV2(vault).slasher() != msg.sender) {
                revert NotSlasher();
            }

            for (uint96 index = getSlotOf(subnetwork, operator); index > 0;) {
                SlotStorage storage slot = slots[index];

                uint208 pendingSlashed = uint208(Math.min(getPending(index, 0), amount));
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

                index = index.getParentIndex();
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
            if (parentIndex.getDepth() > 0) {
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

            if (operator != address(0)) {
                if (_operatorToSlot[operator] > 0) {
                    revert AlreadyAssigned();
                }
                _operatorToSlot[operator] = index;
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

    function setSize(uint96 index, uint128 newSize)
        public
        onlyRole(SET_SIZE_ROLE)
        slotExists(index)
        returns (uint208 pending)
    {
        unchecked {
            SlotStorage storage slot = slots[index];
            uint128 curSize = uint128(slot.size.latest());
            if (curSize == newSize) {
                return 0;
            }

            SlotStorage storage parent = slots[index.getParentIndex()];
            uint48 maxDuration = uint48(IVaultV2(vault).epochDuration() - 1);
            uint256 available = getBalance(index.getParentIndex(), 0);

            if (newSize > curSize) {
                uint256 minAvailable = getBalance(index.getParentIndex(), maxDuration);
                uint208 prevSum = _getPrevSum(index, maxDuration);
                if (uint256(prevSum) + curSize < available && slot.nextSlot.latest() > 0) {
                    uint96 lastIndex = index.getParentIndex().createIndex(uint32(parent.lastChild.latest()));
                    if (
                        newSize - curSize
                            > minAvailable.saturatingSub(
                                uint256(_getPrevSum(lastIndex, 0)) + slots[lastIndex].size.latest()
                                    + getPending(lastIndex, 0)
                            )
                    ) {
                        revert NotEnoughAvailable();
                    }
                }
            } else {
                if (uint256(_getPrevSum(index, 0)) < available) {
                    pending = uint208(getAllocated(index, 0).saturatingSub(getPending(index, 0)).saturatingSub(newSize));
                    if (pending > 0) {
                        slot.pendingCumulative.push(uint48(block.timestamp), slot.pendingCumulative.latest() + pending);
                    }
                }
            }

            slot.size.push(uint48(block.timestamp), newSize);

            emit SetSize(index, newSize);
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

    function _getPrevSum(uint96 index, uint48 duration) internal view returns (uint208 prevSum) {
        if (index == 0) {
            return 0;
        }
        uint96 parentIndex = index.getParentIndex();
        SlotStorage storage parent = slots[parentIndex];
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

    function _getAggregatedAt(uint96 index, uint48 duration, uint48 timestamp) internal view returns (uint256) {
        uint96 parentIndex = index.getParentIndex();
        uint256 slotAvailable = getBalanceAt(parentIndex, duration, timestamp);
        slotAvailable = slotAvailable.saturatingSub(_getPrevSumAt(index, duration, timestamp));
        return Math.min(
            slotAvailable, slots[index].size.upperLookupRecent(timestamp) + getPendingAt(index, duration, timestamp)
        );
    }

    function _getAggregated(uint96 index, uint48 duration) internal view returns (uint256) {
        uint96 parentIndex = index.getParentIndex();
        uint256 slotAvailable = getBalance(parentIndex, duration);
        slotAvailable = slotAvailable.saturatingSub(_getPrevSum(index, duration));
        return Math.min(slotAvailable, slots[index].size.latest() + getPending(index, duration));
    }

    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}

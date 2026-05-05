// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";
import {VaultV2} from "../vault/VaultV2.sol";

import {Checkpoints} from "../libraries/CheckpointsV2.sol";
import {FenwickTreeCheckpoints} from "../libraries/FenwickTreeCheckpoints.sol";
import {Subnetwork} from "../../contracts/libraries/Subnetwork.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {
    IUniversalDelegator,
    CREATE_SLOT_ROLE,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE
} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {VAULT_V2_VERSION} from "../../interfaces/vault/IVaultV2.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";

/// @title UniversalDelegator
/// @notice Contract for stake allocation across network-operator slots.
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
    using Checkpoints for Checkpoints.Trace208;
    using FenwickTreeCheckpoints for FenwickTreeCheckpoints.Tree;

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
        address operator;
        bytes32 subnetwork;
        /// @dev The value is 32 bits for delayedSize pos (can be zero) +
        ///      48 bits for delayedSize timestamp (can be zero) + 128 bits for size value.
        Checkpoints.Trace208 size;
    }

    /// @inheritdoc IUniversalDelegator
    address public vault;
    /// @inheritdoc IUniversalDelegator
    uint32 public totalSlots;

    /// @inheritdoc IUniversalDelegator
    uint32[] public indexesToSync;
    /// @inheritdoc IUniversalDelegator
    mapping(uint32 index => uint32 toSyncIndex) public indexToSyncIndex;

    /// @inheritdoc IUniversalDelegator
    uint128[] public delayedSizes;
    /// @dev Fenwick tree of synced slot size prefix sums by current slot position.
    FenwickTreeCheckpoints.Tree _prevSums;
    /// @dev Slot storage keyed by encoded slot index.
    mapping(uint64 index => SlotStorage slot) internal slots;
    /// @dev Position checkpoints for each slot index.
    mapping(uint32 index => Checkpoints.Trace208) internal _indexToPos;
    /// @dev Synced total slot size checkpoints per subnetwork.
    mapping(bytes32 subnetwork => Checkpoints.Trace208) internal _totalSyncedSize;
    /// @dev Slot index checkpoints keyed by subnetwork and operator.
    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace208 index)) internal _slotOf;

    /// @inheritdoc IUniversalDelegator
    uint48 public migrateTimestamp;
    /// @inheritdoc IUniversalDelegator
    address public oldDelegator;

    /* MODIFIERS */

    /// @dev Synchronize pending size checkpoints before executing the function.
    modifier syncPrevSums() {
        _syncPrevSums();
        _;
    }

    /// @dev Synchronize all due pending slot size checkpoints into prefix sums.
    function _syncPrevSums() internal {
        for (uint256 i; i < indexesToSync.length;) {
            if (_syncPrevSum(indexesToSync[i])) {
                _removeSyncIndex(indexesToSync[i]);
            } else {
                ++i;
            }
        }
    }

    /// @dev Synchronize a due pending size checkpoint into prefix sums.
    function _syncPrevSum(uint32 index) internal returns (bool) {
        uint32 syncIndex = indexToSyncIndex[index];
        if (syncIndex == 0) {
            return false;
        }
        SlotStorage storage slot = slots[index];
        (uint32 delayedSizePos, uint48 delayedTimestamp, uint128 curSize) = _decodeSizeData(slot.size.latest());
        if (delayedTimestamp > block.timestamp) {
            return false;
        }
        uint128 newSize = delayedSizes[delayedSizePos];
        _modifySize(index, -int256(uint256(curSize - newSize)));
        slot.size.push(uint48(block.timestamp), newSize);
        return true;
    }

    /// @dev Remove a slot from the pending prefix-sum synchronization list.
    function _removeSyncIndex(uint32 index) internal returns (bool) {
        uint32 syncIndex = indexToSyncIndex[index];
        if (syncIndex == 0) {
            return false;
        }
        uint32 lastIndex = indexesToSync[indexesToSync.length - 1];
        indexesToSync[syncIndex - 1] = lastIndex;
        indexToSyncIndex[lastIndex] = syncIndex;
        indexesToSync.pop();
        indexToSyncIndex[index] = 0;
        return true;
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
        uint32 index = getSlotOfAt(subnetwork, operator, timestamp);
        return index > 0 ? getAllocatedAt(index, duration, timestamp) : 0;
    }

    /// @inheritdoc IUniversalDelegator
    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        uint32 index = getSlotOf(subnetwork, operator);
        return index > 0 ? getAllocated(index, duration) : 0;
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
        return stakeForAt(subnetwork, operator, _maxDuration(), timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function stake(bytes32 subnetwork, address operator) public view returns (uint256) {
        return stakeFor(subnetwork, operator, _maxDuration());
    }

    /// @inheritdoc IUniversalDelegator
    function getSlot(uint64 index) public view returns (Slot memory) {
        SlotStorage storage slot = slots[index];
        (uint32 delayedSizePos, uint48 delayedTimestamp, uint128 size) = _decodeSizeData(slot.size.latest());
        return Slot({
            exists: slot.exists,
            operator: slot.operator,
            subnetwork: slot.subnetwork,
            size: size,
            delayedTimestamp: delayedTimestamp,
            delayedSize: delayedTimestamp > 0 ? delayedSizes[delayedSizePos] : 0
        });
    }

    /// @inheritdoc IUniversalDelegator
    function getBalanceAt(uint48 duration, uint48 timestamp) public view returns (uint256) {
        return VaultV2(vault).activeStakeAt(timestamp, "") + VaultV2(vault).activeWithdrawalsForAt(duration, timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function getBalance(uint48 duration) public view returns (uint256) {
        return VaultV2(vault).activeStake() + VaultV2(vault).activeWithdrawalsFor(duration);
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocatedAt(uint32 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        if (duration >= VaultV2(vault).epochDuration()) {
            return 0;
        }
        (uint32 delayedSizePos, uint48 delayedTimestamp, uint128 size) =
            _decodeSizeData(slots[index].size.upperLookupRecent(timestamp));
        return Math.min(
            getBalanceAt(duration, timestamp).saturatingSub(_getPrevSumAt(index, timestamp)),
            delayedTimestamp > 0 && delayedTimestamp <= timestamp + duration ? delayedSizes[delayedSizePos] : size
        );
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocated(uint32 index, uint48 duration) public view returns (uint256) {
        if (duration >= VaultV2(vault).epochDuration()) {
            return 0;
        }
        (uint32 delayedSizePos, uint48 delayedTimestamp, uint128 size) = _decodeSizeData(slots[index].size.latest());
        return Math.min(
            getBalance(duration).saturatingSub(_getPrevSum(index)),
            delayedTimestamp > 0 && delayedTimestamp <= uint48(block.timestamp) + duration
                ? delayedSizes[delayedSizePos]
                : size
        );
    }

    /// @inheritdoc IUniversalDelegator
    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp) public view returns (uint32) {
        return uint32(_slotOf[subnetwork][operator].upperLookupRecent(timestamp));
    }

    /// @inheritdoc IUniversalDelegator
    function getSlotOf(bytes32 subnetwork, address operator) public view returns (uint32) {
        return uint32(_slotOf[subnetwork][operator].latest());
    }

    /// @inheritdoc IUniversalDelegator
    function getWithdrawalBuffer() public view returns (uint256) {
        return getBalance(_maxDuration()).saturatingSub(_prevSums.total());
    }

    /// @inheritdoc IUniversalDelegator
    function getTotalSyncedSizeAt(bytes32 subnetwork, uint48 timestamp) public view returns (uint208) {
        return _totalSyncedSize[subnetwork].upperLookupRecent(timestamp);
    }

    /// @inheritdoc IUniversalDelegator
    function getSyncedSizeAt(bytes32 subnetwork, address operator, uint48 timestamp) public view returns (uint128) {
        uint32 index = getSlotOfAt(subnetwork, operator, timestamp);
        if (index == 0) {
            return 0;
        }
        return uint128(slots[index].size.upperLookupRecent(timestamp));
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IUniversalDelegator
    function createSlot(bytes32 subnetwork, address operator, uint128 size)
        public
        onlyRole(CREATE_SLOT_ROLE)
        returns (uint32)
    {
        return _createSlot(subnetwork, operator, size);
    }

    /// @dev Create a new slot.
    function _createSlot(bytes32 subnetwork, address operator, uint128 size)
        internal
        syncPrevSums
        returns (uint32 index)
    {
        if (_slotOf[subnetwork][operator].latest() > 0) {
            revert AlreadyAssigned();
        }

        index = ++totalSlots;
        _indexToPos[index].push(uint48(block.timestamp), index - 1);

        _slotOf[subnetwork][operator].push(uint48(block.timestamp), index);

        SlotStorage storage slot = slots[index];

        slot.exists = true;
        slot.operator = operator;
        slot.subnetwork = subnetwork;

        if (_prevSums.length() < totalSlots) {
            _prevSums.extend();
        }
        if (size > 0) {
            slot.size.push(uint48(block.timestamp), size);
        }
        _modifySize(index, int256(uint256(size)));

        emit CreateSlot(index, size);
    }

    /// @inheritdoc IUniversalDelegator
    function setSize(uint32 index, uint128 newSize) public onlyRole(SET_SIZE_ROLE) syncPrevSums {
        _revertIfNotExists(index);
        // clear pending size decrease
        _removeSyncIndex(index);

        SlotStorage storage slot = slots[index];
        uint128 curSize = uint128(slot.size.latest());
        if (curSize == newSize) {
            if (slot.size.latest() != curSize) {
                slot.size.push(uint48(block.timestamp), curSize);
            }
            return;
        }

        if (newSize > curSize) {
            uint256 delta = newSize - curSize;
            // The provided stake guarantees for all slots are kept even if:
            // - the index's prevSum plus its size is equal to total size => size be increased infinitely,
            // - not the whole slot's size is allocated (the slot is "unfilled") given the max balance => size be increased infinitely,
            // - slot's size is increased less or equal than freely allocatable funds (withdrawal buffer),
            // - otherwise, revert.
            if (
                _prevSums.total() > _prevSums.get(_indexToPos[index].latest())
                    && _getPrevSum(index) + curSize < getBalance(0) && delta > getWithdrawalBuffer()
            ) {
                revert NotEnoughBalance();
            }
            slot.size.push(uint48(block.timestamp), newSize);
            _modifySize(index, int256(delta));
        } else {
            uint256 delta = curSize - newSize;
            uint256 reduced = Math.min(curSize - getAllocated(index, 0), delta);
            // Reduce the current size instatly for "unfilled" part of the slot.
            if (reduced > 0) {
                slot.size.push(uint48(block.timestamp), uint208(curSize - reduced));
                _modifySize(index, -int256(reduced));
            }
            // Create a delayed reduce for the "filled" part of slot.
            if (reduced < delta) {
                slot.size
                    .push(
                        uint48(block.timestamp),
                        _encodeSizeData(
                            uint32(delayedSizes.length),
                            uint48(block.timestamp + VaultV2(vault).epochDuration()),
                            uint128(slot.size.latest())
                        )
                    );
                delayedSizes.push(newSize);
                indexesToSync.push(index);
                indexToSyncIndex[index] = uint32(indexesToSync.length);
            }
        }

        emit SetSize(index, newSize);
    }

    /// @inheritdoc IUniversalDelegator
    function swapSlots(uint32 index1, uint32 index2) public onlyRole(SWAP_SLOTS_ROLE) syncPrevSums {
        _revertIfNotExists(index1);
        _revertIfNotExists(index2);

        uint32 pos1 = uint32(_indexToPos[index1].latest());
        uint32 pos2 = uint32(_indexToPos[index2].latest());
        if (pos1 >= pos2) {
            revert WrongOrder();
        }

        uint128 size1 = uint128(slots[index1].size.latest());
        uint128 size2 = uint128(slots[index2].size.latest());

        // The swap succeeds if:
        // - slot2 fully allocated at maxDuration (epochDuration - 1) => slot1 is fully allocated too,
        // - slot1 unallocated at duration=0 => slot2 is unallocated too,
        // - otherwise, revert.
        if (_getPrevSum(index2) + size2 > getBalance(_maxDuration()) && _getPrevSum(index1) < getBalance(0)) {
            revert NotSameAllocated();
        }

        _indexToPos[index1].push(uint48(block.timestamp), pos2);
        _indexToPos[index2].push(uint48(block.timestamp), pos1);

        int256 delta = int256(uint256(size2)) - int256(uint256(size1));
        _prevSums.modify(pos1, delta);
        _prevSums.modify(pos2, -delta);

        emit SwapSlots(index1, index2);
    }

    /// @inheritdoc IUniversalDelegator
    function removeSlot(uint32 index) public onlyRole(REMOVE_SLOT_ROLE) syncPrevSums {
        _revertIfNotExists(index);
        if (getAllocated(index, 0) > 0) {
            revert SlotAllocated();
        }

        _removeSlot(index);
        emit RemoveSlot(index);
    }

    /// @dev Remove a slot and mark it as non-existent.
    function _removeSlot(uint32 index) internal {
        SlotStorage storage slot = slots[index];

        _slotOf[slot.subnetwork][slot.operator].push(uint48(block.timestamp), 0);

        _removeSyncIndex(index);
        _modifySize(index, -int256(uint256(uint128(slot.size.latest()))));
        slot.size.push(uint48(block.timestamp), 0);

        slot.exists = false;
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

    /// @inheritdoc IUniversalDelegator
    function resetAllocation(bytes32 subnetwork, address operator) public {
        if (
            !IRegistry(NETWORK_REGISTRY).isEntity(subnetwork.network())
                || (subnetwork.network() != msg.sender
                    && INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network())
                        != msg.sender)
        ) {
            revert NotNetworkOrMiddleware();
        }

        uint32 index = getSlotOf(subnetwork, operator);
        _revertIfNotExists(index);

        _syncPrevSum(index);
        _removeSlot(index);

        emit ResetAllocation(index);
    }

    /* PUBLIC FUNCTIONS (INTERNAL LOGIC) */

    /// @inheritdoc IUniversalDelegator
    function onSlash(bytes32 subnetwork, address operator, uint256 amount) public nonReentrant {
        if (VaultV2(vault).slasher() != msg.sender) {
            revert NotSlasher();
        }

        _onSlash(getSlotOf(subnetwork, operator), amount);
    }

    /// @inheritdoc IUniversalDelegator
    function onSlashLegacy(bytes32 subnetwork, address operator, uint256 amount) public nonReentrant {
        if (VaultV2(vault).slasher() != msg.sender) {
            revert NotSlasher();
        }

        uint32 index = getSlotOf(subnetwork, operator);
        if (index == 0 || !slots[index].exists) {
            return;
        }
        _onSlash(index, amount);
    }

    /// @dev Apply slash accounting updates to a slot and its pending checkpoint.
    function _onSlash(uint32 index, uint256 amount) internal {
        if (_syncPrevSum(index)) {
            _removeSyncIndex(index);
        }

        SlotStorage storage slot = slots[index];
        (uint32 delayedSizePos, uint48 delayedTimestamp, uint128 curSize) = _decodeSizeData(slot.size.latest());
        if (curSize < amount) {
            // This is needed only for onSlashLegacy().
            amount = curSize;
        }
        uint128 newSize = uint128(curSize - amount);
        if (delayedTimestamp > 0 && newSize < delayedSizes[delayedSizePos]) {
            delayedSizePos = uint32(delayedSizes.length);
            delayedSizes.push(newSize);
        }
        slot.size.push(uint48(block.timestamp), _encodeSizeData(delayedSizePos, delayedTimestamp, newSize));
        _modifySize(index, -int256(amount));

        emit OnSlash(index, amount);
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

        _prevSums.initialize(1);

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(CREATE_SLOT_ROLE, params.createSlotRoleHolder);
        _grantRoleIfNotZero(SET_SIZE_ROLE, params.setSizeRoleHolder);
        _grantRoleIfNotZero(SWAP_SLOTS_ROLE, params.swapSlotsRoleHolder);
        _grantRoleIfNotZero(REMOVE_SLOT_ROLE, params.removeSlotRoleHolder);

        emit Initialize(params);
    }

    /* MIGRATION */

    /// @inheritdoc IUniversalDelegator
    function migrate(address oldDelegator_) public {
        if (vault != msg.sender) {
            revert NotVault();
        }
        migrateTimestamp = uint48(block.timestamp);
        oldDelegator = oldDelegator_;
    }

    /* UTILITY FUNCTIONS */

    /// @dev Get the prefix sum of previous slot sizes at a timestamp.
    function _getPrevSumAt(uint32 index, uint48 timestamp) internal view returns (uint208 prevSizeSum) {
        uint32 pos = uint32(_indexToPos[index].upperLookupRecent(timestamp));
        if (pos == 0) {
            return 0;
        }
        return uint208(_prevSums.getAt(pos - 1, timestamp));
    }

    /// @dev Get the current prefix sum of previous slot sizes.
    function _getPrevSum(uint32 index) internal view returns (uint208 prevSizeSum) {
        uint32 pos = uint32(_indexToPos[index].latest());
        if (pos == 0) {
            return 0;
        }
        return uint208(_prevSums.get(pos - 1));
    }

    /// @dev Get the maximum slashable duration inside the current vault epoch.
    function _maxDuration() internal view returns (uint48) {
        return VaultV2(vault).epochDuration() - 1;
    }

    /// @dev Revert when a non-zero slot index does not exist.
    function _revertIfNotExists(uint32 index) internal view {
        if (index == 0 || !slots[index].exists) {
            revert SlotNotExists();
        }
    }

    /// @dev Encode delayed size position, delayed timestamp, and synced size into one checkpoint value.
    function _encodeSizeData(uint32 delayedSizePos, uint48 delayedTimestamp, uint128 size)
        internal
        pure
        returns (uint208)
    {
        return uint208(delayedSizePos) << 176 | uint208(delayedTimestamp) << 128 | uint208(size);
    }

    /// @dev Decode one checkpoint value into delayed size position, delayed timestamp, and synced size.
    function _decodeSizeData(uint208 sizeData) internal pure returns (uint32, uint48, uint128) {
        return (uint32(sizeData >> 176), uint48(sizeData >> 128), uint128(sizeData));
    }

    /// @dev Apply a signed delta to the synced total size checkpoint for a subnetwork.
    function _modifySize(uint32 index, int256 delta) internal {
        if (delta == 0) {
            return;
        }
        SlotStorage storage slot = slots[index];
        _prevSums.modify(_indexToPos[index].latest(), delta);
        _totalSyncedSize[slot.subnetwork].push(
            uint48(block.timestamp),
            uint208(uint256(int256(uint256(_totalSyncedSize[slot.subnetwork].latest())) + delta))
        );
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}

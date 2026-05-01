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
        uint32 prevSlot;
        uint32 nextSlot;
        address operator;
        bytes32 subnetwork;
        Checkpoints.Trace208 size;
    }

    /// @inheritdoc IUniversalDelegator
    address public vault;
    uint32 public lastSlot;
    uint32 public firstSlot;
    uint32 public totalSlots;

    uint32[] public syncIndexes;
    mapping(uint32 index => uint32 toSyncIndex) indexToSyncIndex;

    FenwickTreeCheckpoints.Tree _prevSums;
    /// @dev Slot storage keyed by encoded slot index.
    mapping(uint64 index => SlotStorage slot) internal slots;
    mapping(uint32 index => Checkpoints.Trace208) public indexToPos;
    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace208 index)) public _slotOf;

    /// @inheritdoc IUniversalDelegator
    uint48 public migrateTimestamp;
    /// @inheritdoc IUniversalDelegator
    address public oldDelegator;

    /* MODIFIERS */

    /// @dev Synchronize pending size checkpoints before executing the function.
    modifier syncPrevSizeSums() {
        _syncPrevSizeSums();
        _;
    }

    /// @dev Synchronize all due pending slot size checkpoints into prefix sums.
    function _syncPrevSizeSums() internal {
        for (uint256 i; i < syncIndexes.length;) {
            if (!_syncPrevSizeSum(syncIndexes[i])) {
                ++i;
            }
        }
    }

    /// @dev Synchronize a due pending size checkpoint into prefix sums.
    function _syncPrevSizeSum(uint32 index) internal returns (bool) {
        uint32 syncIndex = indexToSyncIndex[index];
        if (syncIndex == 0) {
            return false;
        }
        Checkpoints.Trace208 storage sizeCheckpoints = slots[index].size;
        (, uint48 latestTimestamp, uint208 latestSize) = sizeCheckpoints.latestCheckpoint();
        if (latestTimestamp > block.timestamp) {
            return false;
        }
        _prevSums.modify(
            indexToPos[index].latest(),
            int256(uint256(latestSize))
                - int256(uint256(sizeCheckpoints.at(uint32(sizeCheckpoints.length() - 2))._value))
        );
        _clearSyncPrevSizeSum(index);
        return true;
    }

    /// @dev Remove a slot from the pending prefix-sum synchronization list.
    function _clearSyncPrevSizeSum(uint32 index) internal returns (bool) {
        uint32 syncIndex = indexToSyncIndex[index];
        if (syncIndex == 0) {
            return false;
        }
        uint32 lastIndex = syncIndexes[syncIndexes.length - 1];
        syncIndexes[syncIndex - 1] = lastIndex;
        indexToSyncIndex[lastIndex] = syncIndex;
        syncIndexes.pop();
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
        return Slot({
            exists: slot.exists,
            prevSlot: slot.prevSlot,
            nextSlot: slot.nextSlot,
            operator: slot.operator,
            subnetwork: slot.subnetwork,
            size: getSize(index),
            latestSize: uint128(slot.size.latest())
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
        return Math.min(
            getBalanceAt(duration, timestamp).saturatingSub(_getPrevSumAt(index, timestamp)),
            getSizeAt(index, timestamp + duration)
        );
    }

    /// @inheritdoc IUniversalDelegator
    function getAllocated(uint32 index, uint48 duration) public view returns (uint256) {
        if (duration >= VaultV2(vault).epochDuration()) {
            return 0;
        }
        return Math.min(
            getBalance(duration).saturatingSub(_getPrevSum(index)), getSizeAt(index, uint48(block.timestamp) + duration)
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
    function getSizeAt(uint64 index, uint48 timestamp) public view returns (uint128) {
        return uint128(slots[index].size.upperLookupRecent(timestamp));
    }

    /// @inheritdoc IUniversalDelegator
    function getSize(uint64 index) public view returns (uint128) {
        return uint128(slots[index].size.upperLookupRecent(uint48(block.timestamp)));
    }

    /// @inheritdoc IUniversalDelegator
    function getWithdrawalBuffer() public view returns (uint256) {
        return getBalance(_maxDuration()).saturatingSub(_getPrevSum(lastSlot) + getSize(lastSlot));
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
        syncPrevSizeSums
        returns (uint32 index)
    {
        if (_slotOf[subnetwork][operator].latest() > 0) {
            revert();
        }

        index = ++totalSlots;
        indexToPos[index].push(uint48(block.timestamp), totalSlots - 1);

        _slotOf[subnetwork][operator].push(uint48(block.timestamp), index);

        SlotStorage storage slot = slots[index];

        slot.exists = true;
        slot.operator = operator;
        slot.subnetwork = subnetwork;
        if (firstSlot == 0) {
            firstSlot = index;
        } else {
            slots[lastSlot].nextSlot = index;
            slot.prevSlot = lastSlot;
        }
        lastSlot = index;
        if (size > 0) {
            slot.size.push(uint48(block.timestamp), size);
        }

        if (_prevSums.length() < totalSlots) {
            _prevSums.extend();
        }
        _prevSums.modify(index - 1, int256(uint256(size)));

        emit CreateSlot(index, size);
    }

    /// @inheritdoc IUniversalDelegator
    function setSize(uint32 index, uint128 newSize) public onlyRole(SET_SIZE_ROLE) syncPrevSizeSums {
        _revertIfNotExists(index);

        SlotStorage storage slot = slots[index];
        uint128 curSize = getSize(index);
        if (curSize == newSize) {
            return;
        }

        if (_clearSyncPrevSizeSum(index)) {
            slots[index].size.pop();
        }

        if (newSize > curSize) {
            uint128 delta = newSize - curSize;
            if (_getPrevSum(index) + curSize < getBalance(0) && slot.nextSlot > 0 && delta > getWithdrawalBuffer()) {
                revert NotEnoughBalance();
            }
            slot.size.push(uint48(block.timestamp), newSize);
            _prevSums.modify(indexToPos[index].latest(), int256(uint256(delta)));
        } else {
            uint128 delta = curSize - newSize;
            uint256 reduced = Math.min(uint256(curSize).saturatingSub(getAllocated(index, 0)), uint256(delta));
            if (reduced > 0) {
                slot.size.push(uint48(block.timestamp), uint208(curSize - reduced));
                _prevSums.modify(indexToPos[index].latest(), -int256(reduced));
            }
            if (reduced < delta) {
                slot.size.push(uint48(block.timestamp) + VaultV2(vault).epochDuration(), newSize);
                syncIndexes.push(index);
                indexToSyncIndex[index] = uint32(syncIndexes.length);
            }
        }

        emit SetSize(index, newSize);
    }

    /// @inheritdoc IUniversalDelegator
    function swapSlots(uint32 index1, uint32 index2) public onlyRole(SWAP_SLOTS_ROLE) syncPrevSizeSums {
        _revertIfNotExists(index1);
        _revertIfNotExists(index2);

        uint32 pos1 = uint32(indexToPos[index1].latest());
        uint32 pos2 = uint32(indexToPos[index2].latest());
        if (pos1 >= pos2) {
            revert();
        }

        uint256 minBalance = getBalance(_maxDuration());
        uint256 curPrevSum = _getPrevSum(index2);
        // - slot2 fully allocated at maxDuration (epochDuration - 1) => slot1 is fully allocated too,
        // - slot1 unallocated at duration=0 => slot2 is unallocated too,
        // - otherwise, revert.
        if (curPrevSum < minBalance) {
            if (curPrevSum + getSize(index2) > minBalance) {
                revert PartiallyAllocated();
            }
        } else if (_getPrevSum(index1) < getBalance(0)) {
            revert NotSameAllocated();
        }

        indexToPos[index1].push(uint48(block.timestamp), pos2);
        indexToPos[index2].push(uint48(block.timestamp), pos1);

        int256 delta = int256(uint256(getSize(index2))) - int256(uint256(getSize(index1)));
        _prevSums.modify(pos1, delta);
        _prevSums.modify(pos2, -delta);

        if (index1 == firstSlot) {
            firstSlot = index2;
        }
        if (index2 == lastSlot) {
            lastSlot = index1;
        }

        SlotStorage storage slot1 = slots[index1];
        SlotStorage storage slot2 = slots[index2];

        (slot1.nextSlot, slot2.nextSlot) = (slot2.nextSlot, slot1.nextSlot);

        if (slot1.nextSlot > 0) {
            slots[slot1.nextSlot].prevSlot = index1;
        }
        slots[slot2.nextSlot].prevSlot = index2;

        (slot1.prevSlot, slot2.prevSlot) = (slot2.prevSlot, slot1.prevSlot);

        slots[slot1.prevSlot].nextSlot = index1;
        if (slot2.prevSlot > 0) {
            slots[slot2.prevSlot].nextSlot = index2;
        }

        emit SwapSlots(index1, index2);
    }

    /// @inheritdoc IUniversalDelegator
    function removeSlot(uint32 index) public onlyRole(REMOVE_SLOT_ROLE) syncPrevSizeSums {
        _revertIfNotExists(index);
        if (getAllocated(index, 0) > 0) {
            revert SlotAllocated();
        }

        _removeSlot(index);
        emit RemoveSlot(index);
    }

    /// @dev Remove a slot from the linked-list structure and mark it as non-existent.
    function _removeSlot(uint32 index) internal {
        SlotStorage storage slot = slots[index];

        _slotOf[slot.subnetwork][slot.operator].push(uint48(block.timestamp), 0);

        if (_clearSyncPrevSizeSum(index)) {
            slots[index].size.pop();
        }
        _prevSums.modify(indexToPos[index].latest(), -int256(uint256(getSize(index))));

        if (index == firstSlot) {
            firstSlot = slot.nextSlot;
        } else {
            slots[slot.prevSlot].nextSlot = slot.nextSlot;
        }
        if (index == lastSlot) {
            lastSlot = slot.prevSlot;
        } else {
            slots[slot.nextSlot].prevSlot = slot.prevSlot;
        }

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

        _removeSlot(index);

        emit ResetAllocation(index, subnetwork);
    }

    /* PUBLIC FUNCTIONS (INTERNAL LOGIC) */

    /// @inheritdoc IUniversalDelegator
    function onSlash(bytes32 subnetwork, address operator, uint256 amount) public nonReentrant {
        if (VaultV2(vault).slasher() != msg.sender) {
            revert NotSlasher();
        }

        _onSlash(getSlotOf(subnetwork, operator), amount);

        emit OnSlash(subnetwork, operator, amount);
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

        emit OnSlashLegacy(amount);
    }

    /// @dev Apply slash accounting updates to a slot and its pending checkpoint.
    function _onSlash(uint32 index, uint256 amount) internal {
        if (index == 0) {
            return;
        }
        _syncPrevSizeSum(index);

        SlotStorage storage slot = slots[index];
        (bool exists, uint48 latestTimestamp, uint208 latestSize) = slot.size.latestCheckpoint();
        if (exists && latestTimestamp > block.timestamp) {
            slot.size.pop();
        }

        slot.size.push(uint48(block.timestamp), uint208(slot.size.latest() - amount));
        _prevSums.modify(indexToPos[index].latest(), -int256(amount));

        if (exists && latestTimestamp > block.timestamp) {
            uint208 futureSize = uint208(Math.min(slot.size.latest(), latestSize));
            slot.size.push(latestTimestamp, futureSize);
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
        uint32 pos = uint32(indexToPos[index].upperLookupRecent(timestamp));
        if (pos == 0) {
            return 0;
        }
        return uint208(_prevSums.getAt(pos - 1, timestamp));
    }

    /// @dev Get the current prefix sum of previous slot sizes.
    function _getPrevSum(uint32 index) internal view returns (uint208 prevSizeSum) {
        uint32 pos = uint32(indexToPos[index].latest());
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

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}

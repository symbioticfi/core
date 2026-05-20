// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";
import {VaultV2} from "../vault/VaultV2.sol";

import {FenwickTreeCheckpoints} from "../libraries/FenwickTreeCheckpoints.sol";
import {Subnetwork} from "../../contracts/libraries/Subnetwork.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBurner} from "../../interfaces/slasher/IBurner.sol";
import {IDelegator} from "../../interfaces/delegator/IDelegator.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {
    IGuaranteesDelegator,
    BURNER_GAS_LIMIT,
    BURNER_RESERVE,
    CREATE_SLOT_ROLE,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE
} from "../../interfaces/delegator/IGuaranteesDelegator.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {MAX_DURATION, VAULT_V2_VERSION} from "../../interfaces/vault/IVaultV2.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title GuaranteesDelegator
/// @notice Contract for stake allocation across network-operator slots.
contract GuaranteesDelegator is
    Entity,
    StaticDelegateCallable,
    AccessControlUpgradeable,
    ReentrancyGuard,
    IGuaranteesDelegator
{
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using FenwickTreeCheckpoints for FenwickTreeCheckpoints.Tree;

    /* IMMUTABLES */

    /// @dev Address of the vault factory.
    address internal immutable VAULT_FACTORY;
    /// @dev Address of the network registry.
    address internal immutable NETWORK_REGISTRY;
    /// @dev Address of the network middleware service.
    address internal immutable NETWORK_MIDDLEWARE_SERVICE;

    /* STATE VARIABLES */

    struct SlotStorage {
        bool exists;
        uint48 slashedAt;
        address operator;
        bytes32 subnetwork;
        /// @dev The value is 32 bits for delayedSize pos (can be zero) +
        ///      48 bits for delayedSize timestamp (can be zero) + 128 bits for size value.
        Checkpoints.Trace208 size;
        Checkpoints.Trace208 slashed;
    }

    /// @inheritdoc IDelegator
    address public vault;

    Checkpoints.Trace256 internal _totalIncrease;
    Checkpoints.Trace256 internal _totalDecrease;

    /// @inheritdoc IGuaranteesDelegator
    uint32 public totalSlots;
    /// @inheritdoc IGuaranteesDelegator
    uint32[] public indexesToSync;
    /// @inheritdoc IGuaranteesDelegator
    mapping(uint32 index => uint32 toSyncIndex) public indexToSyncIndex;

    /// @inheritdoc IGuaranteesDelegator
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

    /// @inheritdoc IGuaranteesDelegator
    bool public isBurnerHook;
    /// @inheritdoc IGuaranteesDelegator
    uint48 public vetoDuration;
    /// @inheritdoc IGuaranteesDelegator
    uint48 public resolverSetDelay;
    /// @inheritdoc IGuaranteesDelegator
    mapping(bytes32 subnetwork => bytes32 value) public pendingResolverData;

    /// @dev Slash request storage.
    SlashRequest[] internal _slashRequests;
    /// @dev Active resolver per subnetwork.
    mapping(bytes32 subnetwork => address value) internal _resolver;

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
        uint128 newSize = curSize;

        if (slot.slashedAt > 0) {
            if (slot.slashedAt <= block.timestamp - VaultV2(vault).epochDuration()) {
                newSize = uint128(uint256(newSize).saturatingSub(slot.slashed.latest()));
                slot.slashed.push(uint48(block.timestamp), 0);
                slot.slashedAt = 0;
            }
        }
        bool flag = true;
        if (delayedTimestamp > 0) {
            if (delayedTimestamp <= block.timestamp) {
                newSize = uint128(Math.min(delayedSizes[delayedSizePos], newSize));
            } else {
                flag = false;
            }
        }
        if (newSize != curSize) {
            _modifySize(index, -int256(uint256(curSize - newSize)));
            slot.size
                .push(
                    uint48(block.timestamp), flag ? newSize : _encodeSizeData(delayedSizePos, delayedTimestamp, newSize)
                );
        }
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

    /// @inheritdoc IGuaranteesDelegator
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
        uint64 entityType,
        address vaultFactory,
        address networkRegistry,
        address delegatorFactory,
        address networkMiddlewareService
    ) Entity(delegatorFactory, entityType) {
        VAULT_FACTORY = vaultFactory;
        NETWORK_REGISTRY = networkRegistry;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
    }

    /// @inheritdoc IGuaranteesDelegator
    function VERSION() public pure returns (uint64) {
        return 2;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IGuaranteesDelegator
    function stakeForAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        public
        view
        returns (uint256)
    {
        uint32 index = getSlotOfAt(subnetwork, operator, timestamp);
        return index > 0 ? getAllocatedAt(index, duration, timestamp) : 0;
    }

    /// @inheritdoc IGuaranteesDelegator
    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) public view returns (uint256) {
        uint32 index = getSlotOf(subnetwork, operator);
        return index > 0 ? getAllocated(index, duration) : 0;
    }

    /// @inheritdoc IGuaranteesDelegator
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes calldata)
        public
        view
        returns (uint256)
    {
        return stakeForAt(subnetwork, operator, _maxDuration(), timestamp);
    }

    /// @inheritdoc IGuaranteesDelegator
    function stake(bytes32 subnetwork, address operator) public view returns (uint256) {
        return stakeFor(subnetwork, operator, _maxDuration());
    }

    /// @inheritdoc IGuaranteesDelegator
    function getSlot(uint32 index) public view returns (Slot memory) {
        SlotStorage storage slot = slots[index];
        (uint32 delayedSizePos, uint48 delayedTimestamp, uint128 size) = _decodeSizeData(slot.size.latest());
        return Slot({
            pos: uint32(_indexToPos[index].latest()),
            exists: slot.exists,
            operator: slot.operator,
            subnetwork: slot.subnetwork,
            size: size,
            delayedTimestamp: delayedTimestamp,
            delayedSize: delayedTimestamp > 0 ? delayedSizes[delayedSizePos] : 0
        });
    }

    /// @inheritdoc IGuaranteesDelegator
    function getBalanceAt(uint48 duration, uint48 timestamp) public view returns (uint256) {
        return _totalIncrease.upperLookupRecent(timestamp) - _totalDecrease.upperLookupRecent(timestamp + duration);
    }

    /// @inheritdoc IGuaranteesDelegator
    function getBalance(uint48 duration) public view returns (uint256) {
        return _totalIncrease.latest() - _totalDecrease.upperLookupRecent(block.timestamp + duration);
    }

    /// @inheritdoc IDelegator
    function totalAssets() public view returns (uint256) {
        return 0;
    }

    /// @inheritdoc IGuaranteesDelegator
    function getAllocatedAt(uint32 index, uint48 duration, uint48 timestamp) public view returns (uint256) {
        if (duration >= VaultV2(vault).epochDuration()) {
            return 0;
        }
        SlotStorage storage slot = slots[index];
        (uint32 delayedSizePos, uint48 delayedTimestamp, uint128 size) =
            _decodeSizeData(slot.size.upperLookupRecent(timestamp));
        return Math.min(
            getBalanceAt(duration, timestamp).saturatingSub(_getPrevSumAt(index, timestamp)),
            delayedTimestamp > 0 && delayedTimestamp <= timestamp + duration
                ? Math.min(delayedSizes[delayedSizePos], size - slot.slashed.upperLookupRecent(timestamp))
                : size - slot.slashed.upperLookupRecent(timestamp)
        );
    }

    /// @inheritdoc IGuaranteesDelegator
    function getAllocated(uint32 index, uint48 duration) public view returns (uint256) {
        if (duration >= VaultV2(vault).epochDuration()) {
            return 0;
        }
        SlotStorage storage slot = slots[index];
        (uint32 delayedSizePos, uint48 delayedTimestamp, uint128 size) = _decodeSizeData(slot.size.latest());
        return Math.min(
            getBalance(duration).saturatingSub(_getPrevSum(index)),
            delayedTimestamp > 0 && delayedTimestamp <= uint48(block.timestamp) + duration
                ? Math.min(delayedSizes[delayedSizePos], size - slot.slashed.latest())
                : size - slot.slashed.latest()
        );
    }

    /// @inheritdoc IGuaranteesDelegator
    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp) public view returns (uint32) {
        return uint32(_slotOf[subnetwork][operator].upperLookupRecent(timestamp));
    }

    /// @inheritdoc IGuaranteesDelegator
    function getSlotOf(bytes32 subnetwork, address operator) public view returns (uint32) {
        return uint32(_slotOf[subnetwork][operator].latest());
    }

    /// @inheritdoc IGuaranteesDelegator
    function totalAllocated() public syncPrevSums returns (uint256 allocated) {
        return Math.min(getBalance(0), _prevSums.total());
    }

    /// @inheritdoc IGuaranteesDelegator
    function getTotalSyncedSizeAt(bytes32 subnetwork, uint48 timestamp) public view returns (uint208) {
        return _totalSyncedSize[subnetwork].upperLookupRecent(timestamp);
    }

    /// @inheritdoc IGuaranteesDelegator
    function getSyncedSizeAt(bytes32 subnetwork, address operator, uint48 timestamp) public view returns (uint128) {
        uint32 index = getSlotOfAt(subnetwork, operator, timestamp);
        if (index == 0) {
            return 0;
        }
        return uint128(slots[index].size.upperLookupRecent(timestamp));
    }

    /// @inheritdoc IGuaranteesDelegator
    function slashRequestsLength() public view returns (uint256) {
        return _slashRequests.length;
    }

    /// @inheritdoc IGuaranteesDelegator
    function slashRequests(uint256 slashIndex) public view returns (SlashRequest memory) {
        return _slashRequests[slashIndex];
    }

    /// @inheritdoc IGuaranteesDelegator
    function resolver(bytes32 subnetwork) public view returns (address) {
        return uint48(uint256(pendingResolverData[subnetwork])) == 0
            || block.timestamp < uint48(uint256(pendingResolverData[subnetwork]))
            ? _resolver[subnetwork]
            : address(uint160(uint256(pendingResolverData[subnetwork]) >> 48));
    }

    /// @inheritdoc IGuaranteesDelegator
    function slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes calldata)
        public
        view
        returns (uint256)
    {
        if (
            captureTimestamp > 0
                && (captureTimestamp <= block.timestamp.saturatingSub(VaultV2(vault).epochDuration())
                    || captureTimestamp > block.timestamp)
        ) {
            return 0;
        }
        return GuaranteesDelegator(VaultV2(vault).delegator()).stakeFor(subnetwork, operator, 0);
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IGuaranteesDelegator
    function createSlot(bytes32 subnetwork, address operator, uint128 size)
        public
        onlyRole(CREATE_SLOT_ROLE)
        syncPrevSums
        returns (uint32 index)
    {
        if (_slotOf[subnetwork][operator].latest() > 0) {
            revert AlreadyAssigned();
        }
        if (subnetwork == bytes32(0) || operator == address(0)) {
            revert InvalidNetOrOp();
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

        emit CreateSlot(index, subnetwork, operator, size);
    }

    /// @inheritdoc IGuaranteesDelegator
    function setSize(uint32 index, uint128 newSize) public onlyRole(SET_SIZE_ROLE) syncPrevSums {
        _revertIfNotExists(index);
        // clear pending size decrease
        _removeSyncIndex(index);

        SlotStorage storage slot = slots[index];
        uint128 curSize = uint128(slot.size.latest());
        if (newSize >= curSize) {
            uint256 delta = newSize - curSize;
            // The provided stake guarantees for all slots are kept even if:
            // - the index's prevSum plus its size is equal to total size => size be increased infinitely,
            // - not the whole slot's size is allocated (the slot is "unfilled") given the max balance => size be increased infinitely,
            // - slot's size is increased less or equal than freely allocatable funds (withdrawal buffer),
            // - otherwise, revert.
            if (
                _prevSums.total() > _prevSums.get(_indexToPos[index].latest())
                    && _getPrevSum(index) + curSize < getBalance(0)
                    && delta > getBalance(_maxDuration()) - totalAllocated()
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

    /// @inheritdoc IGuaranteesDelegator
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

    /// @inheritdoc IGuaranteesDelegator
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

    /// @inheritdoc IGuaranteesDelegator
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

    /// @inheritdoc IGuaranteesDelegator
    function slash(bytes32 subnetwork, address operator, uint256 amount, uint48, bytes calldata)
        external
        returns (uint256)
    {
        return executeSlash(requestSlash(subnetwork, operator, amount, 0, Calldata.emptyBytes()), Calldata.emptyBytes());
    }

    /// @inheritdoc IGuaranteesDelegator
    function requestSlash(bytes32 subnetwork, address operator, uint256 amount, uint48, bytes calldata)
        public
        nonReentrant
        returns (uint256 slashIndex)
    {
        _checkNetworkMiddleware(subnetwork);

        amount = Math.min(amount, slashableStake(subnetwork, operator, 0, Calldata.emptyBytes()));
        if (amount == 0) {
            revert InsufficientSlash();
        }

        address curResolver = resolver(subnetwork);
        uint48 vetoDeadline = uint48(block.timestamp) + (curResolver != address(0) ? vetoDuration : 0);

        slashIndex = _slashRequests.length;
        _slashRequests.push(
            SlashRequest({
                subnetwork: subnetwork,
                operator: operator,
                amount: amount,
                createdAt: uint48(block.timestamp),
                resolver: curResolver,
                vetoDeadline: vetoDeadline,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, subnetwork, operator, amount, vetoDeadline);
    }

    /// @inheritdoc IGuaranteesDelegator
    function executeSlash(uint256 slashIndex, bytes calldata) public nonReentrant returns (uint256 slashedAmount) {
        SlashRequest memory request = slashRequests(slashIndex);

        _checkNetworkMiddleware(request.subnetwork);

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        if (request.vetoDeadline > block.timestamp) {
            revert VetoPeriodNotEnded();
        }

        slashedAmount = Math.min(
            request.amount,
            slashableStake(request.subnetwork, request.operator, request.createdAt, Calldata.emptyBytes())
        );
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        _slashRequests[slashIndex].completed = true;

        uint32 index = getSlotOf(request.subnetwork, request.operator);
        if (_syncPrevSum(index)) {
            _removeSyncIndex(index);
        }

        SlotStorage storage slot = slots[index];
        slot.slashedAt = uint48(block.timestamp);
        slot.slashed.push(uint48(block.timestamp), slot.slashed.latest() + uint208(slashedAmount));
        _totalDecrease.push(
            uint48(block.timestamp) + VaultV2(vault).epochDuration(),
            _totalDecrease.latest() + slashedAmount.mulDiv(VaultV2(vault).activeStake(), VaultV2(vault).totalStake())
        );

        if (indexToSyncIndex[index] == 0) {
            indexesToSync.push(index);
            indexToSyncIndex[index] = uint32(indexesToSync.length);
        }

        VaultV2(vault).onSlash(slashedAmount);

        _burnerOnSlash(request.subnetwork, request.operator, slashedAmount);

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /// @inheritdoc IGuaranteesDelegator
    function vetoSlash(uint256 slashIndex) public nonReentrant {
        SlashRequest memory request = slashRequests(slashIndex);

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        if (request.resolver != msg.sender) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= block.timestamp) {
            revert VetoPeriodEnded();
        }

        _slashRequests[slashIndex].completed = true;

        emit VetoSlash(slashIndex, msg.sender);
    }

    /// @inheritdoc IGuaranteesDelegator
    function setResolver(uint96 identifier, address newResolver) public nonReentrant {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        bytes32 subnetwork = (msg.sender).subnetwork(identifier);
        address curResolver = resolver(subnetwork);

        if (curResolver == address(0)) {
            _resolver[subnetwork] = newResolver;
            pendingResolverData[subnetwork] = 0;
        } else {
            _resolver[subnetwork] = curResolver;
            pendingResolverData[subnetwork] =
                bytes32(uint256(uint160(newResolver)) << 48 | (block.timestamp + resolverSetDelay));
        }

        emit SetResolver(subnetwork, newResolver);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IDelegator
    function sync() public {
        if (VaultV2(vault).withdrawalQueue() != msg.sender) {
            revert NotVault();
        }

        _syncPrevSums();
    }

    /// @inheritdoc IDelegator
    function onDeposit(address caller, address receiver, uint256 assets, uint256 shares) public nonReentrant {
        if (vault != msg.sender) {
            revert NotVault();
        }

        _totalIncrease.push(uint48(block.timestamp), _totalIncrease.latest() + assets);

        emit OnDeposit(caller, receiver, assets, shares);
    }

    /// @inheritdoc IDelegator
    function onRequestWithdraw(address caller, address receiver, uint256 assets, uint256 shares) public nonReentrant {
        if (VaultV2(vault).withdrawalQueue() != msg.sender) {
            revert NotVault();
        }

        _totalDecrease.push(uint48(block.timestamp) + VaultV2(vault).epochDuration(), _totalDecrease.latest() + assets);

        emit OnRequestWithdraw(caller, receiver, assets, shares);
    }

    /// @inheritdoc IDelegator
    function onWithdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        public
        nonReentrant
    {
        if (vault != msg.sender) {
            revert NotVault();
        }

        if (VaultV2(vault).totalAssets() - assets < totalAllocated()) {
            revert();
        }

        emit OnWithdraw(caller, receiver, owner, assets, shares);
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

        vault = initVault;

        _prevSums.initialize(1);

        if (params.vetoDuration >= VaultV2(initVault).epochDuration()) {
            revert InvalidVetoDuration();
        }

        if (params.resolverSetDelay <= VaultV2(initVault).epochDuration() || params.resolverSetDelay > MAX_DURATION) {
            revert InvalidResolverSetEpochsDelay();
        }

        if (VaultV2(initVault).burner() == address(0) && params.isBurnerHook) {
            revert NoBurner();
        }

        vault = initVault;

        isBurnerHook = params.isBurnerHook;
        vetoDuration = params.vetoDuration;
        resolverSetDelay = params.resolverSetDelay;

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(CREATE_SLOT_ROLE, params.createSlotRoleHolder);
        _grantRoleIfNotZero(SET_SIZE_ROLE, params.setSizeRoleHolder);
        _grantRoleIfNotZero(SWAP_SLOTS_ROLE, params.swapSlotsRoleHolder);
        _grantRoleIfNotZero(REMOVE_SLOT_ROLE, params.removeSlotRoleHolder);

        emit Initialize(params);
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

    /// @dev Revert unless caller is the middleware configured for the request subnetwork.
    function _checkNetworkMiddleware(bytes32 subnetwork) internal view {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }
    }

    /// @dev Call the burner hook after a slash when burner hook mode is enabled.
    function _burnerOnSlash(bytes32 subnetwork, address operator, uint256 amount) internal {
        if (isBurnerHook) {
            address burner = VaultV2(vault).burner();
            bytes memory burnerCalldata = abi.encodeCall(IBurner.onSlash, (subnetwork, operator, amount, 0));

            if (gasleft() < BURNER_RESERVE + BURNER_GAS_LIMIT * 64 / 63) {
                revert InsufficientBurnerGas();
            }

            assembly ("memory-safe") {
                pop(call(BURNER_GAS_LIMIT, burner, 0, add(burnerCalldata, 0x20), mload(burnerCalldata), 0, 0))
            }
        }
    }
}

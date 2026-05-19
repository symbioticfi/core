// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDelegator} from "./IDelegator.sol";

uint64 constant GUARANTEES_DELEGATOR_TYPE = 4;

uint256 constant BURNER_GAS_LIMIT = 150_000;
uint256 constant BURNER_RESERVE = 20_000;

// Keccak256("CREATE_SLOT_ROLE").
bytes32 constant CREATE_SLOT_ROLE = 0x8aef711962d032b5812b71f6f4353b179696ada38e16233a26a539c32c729007;
// Keccak256("SET_SIZE_ROLE").
bytes32 constant SET_SIZE_ROLE = 0xc9c130a1412d72f4d79081ca47a83fb21e212d7ff57949aadd2c1356e17ee837;
// Keccak256("SWAP_SLOTS_ROLE").
bytes32 constant SWAP_SLOTS_ROLE = 0xffd98ac79bb60993f79efa77ec34b3f446950a5c284ae3036fc0fb810a00af60;
// Keccak256("REMOVE_SLOT_ROLE").
bytes32 constant REMOVE_SLOT_ROLE = 0x1cbee842b8b18f1dea4a0fb8117bb405b26bede02a0f7f47acb5d727ef90e6f4;

/**
 * @title IGuaranteesDelegator
 * @notice Interface for the GuaranteesDelegator contract.
 */
interface IGuaranteesDelegator is IDelegator {
    /* ERRORS */

    /**
     * @notice Raised when a network or operator is already assigned to a slot.
     */
    error AlreadyAssigned();

    /**
     * @notice Raised when there is not enough gas left for the burner hook call.
     */
    error InsufficientBurnerGas();

    /**
     * @notice Raised when the requested slash amount is zero after validation.
     */
    error InsufficientSlash();

    /**
     * @notice Raised when the provided subnetwork or operator is zero.
     */
    error InvalidNetOrOp();

    /**
     * @notice Raised when the resolver set delay is outside allowed bounds.
     */
    error InvalidResolverSetEpochsDelay();

    /**
     * @notice Raised when the veto duration is outside allowed bounds.
     */
    error InvalidVetoDuration();

    /**
     * @notice Raised when burner-hook mode is enabled but the vault has no burner.
     */
    error NoBurner();

    /**
     * @notice Raised when there is not enough balance for the operation.
     */
    error NotEnoughBalance();

    /**
     * @notice Raised when the caller is not a registered network.
     */
    error NotNetwork();

    /**
     * @notice Raised when the caller is not the network middleware for the subnetwork.
     */
    error NotNetworkMiddleware();

    /**
     * @notice Raised when the caller is neither a network nor its middleware.
     */
    error NotNetworkOrMiddleware();

    /**
     * @notice Raised when the caller is not the configured resolver.
     */
    error NotResolver();

    /**
     * @notice Raised when two slots are not in the same allocation state.
     */
    error NotSameAllocated();

    /**
     * @notice Raised when the provided vault is invalid.
     */
    error NotVault();

    /**
     * @notice Raised when the connected vault version is older than required.
     */
    error OldVault();

    /**
     * @notice Raised when the requested slash request has already been completed.
     */
    error SlashRequestCompleted();

    /**
     * @notice Raised when trying to remove a slot that still has allocation.
     */
    error SlotAllocated();

    /**
     * @notice Raised when the requested slot does not exist.
     */
    error SlotNotExists();

    /**
     * @notice Raised when the resolver attempts to veto after the veto period ended.
     */
    error VetoPeriodEnded();

    /**
     * @notice Raised when slash execution is attempted before the veto period ends.
     */
    error VetoPeriodNotEnded();

    /**
     * @notice Raised when slot ordering constraints are violated.
     */
    error WrongOrder();

    /* STRUCTS */

    /**
     * @notice Slot snapshot data.
     * @param pos Current slot position.
     * @param exists Whether the slot exists.
     * @param operator Operator assigned to the slot.
     * @param subnetwork Subnetwork assigned to the slot.
     * @param size Latest synced slot size checkpoint value.
     * @param delayedTimestamp Timestamp when the delayed size becomes effective, or zero when there is no delay.
     * @param delayedSize Delayed target size, or zero when there is no delay.
     */
    struct Slot {
        uint32 pos;
        bool exists;
        address operator;
        bytes32 subnetwork;
        uint128 size;
        uint48 delayedTimestamp;
        uint128 delayedSize;
    }

    /**
     * @notice Slash request data.
     * @param subnetwork Subnetwork that requested the slash.
     * @param operator Operator subject to the slash request.
     * @param createdAt Timestamp when the request was created.
     * @param amount Maximum slash amount requested.
     * @param resolver Resolver allowed to veto the request.
     * @param vetoDeadline Timestamp before which the resolver can veto the request.
     * @param completed Whether the request was executed or vetoed.
     */
    struct SlashRequest {
        bytes32 subnetwork;
        address operator;
        uint48 createdAt;
        uint256 amount;
        address resolver;
        uint48 vetoDeadline;
        bool completed;
    }

    /**
     * @notice Initialization parameters for the guarantees delegator.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param createSlotRoleHolder Address of the initial CREATE_SLOT_ROLE holder.
     * @param setSizeRoleHolder Address of the initial SET_SIZE_ROLE holder.
     * @param swapSlotsRoleHolder Address of the initial SWAP_SLOTS_ROLE holder.
     * @param removeSlotRoleHolder Address of the initial REMOVE_SLOT_ROLE holder.
     * @param isBurnerHook Whether burner hook calls are enabled on slashes.
     * @param vetoDuration Duration of the veto period for slash requests.
     * @param resolverSetDelay Delay before resolver updates become active.
     */
    struct InitParams {
        address defaultAdminRoleHolder;
        address createSlotRoleHolder;
        address setSizeRoleHolder;
        address swapSlotsRoleHolder;
        address removeSlotRoleHolder;
        bool isBurnerHook;
        uint48 vetoDuration;
        uint48 resolverSetDelay;
    }

    /**
     * @notice Base parameters needed for delegators' deployment.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     */
    struct BaseParams {
        address defaultAdminRoleHolder;
    }

    /* EVENTS */

    /**
     * @notice Emitted when a slot is created.
     * @param index Index of the created slot.
     * @param subnetwork Subnetwork assigned to the slot.
     * @param operator Operator assigned to the slot.
     * @param size Initial slot size.
     */
    event CreateSlot(uint32 indexed index, bytes32 subnetwork, address operator, uint128 size);

    /**
     * @notice Emitted when a slot size is updated.
     * @param index Slot index.
     * @param size New slot size.
     */
    event SetSize(uint32 indexed index, uint128 size);

    /**
     * @notice Emitted when two slots are swapped.
     * @param index1 First slot index.
     * @param index2 Second slot index.
     */
    event SwapSlots(uint32 indexed index1, uint32 indexed index2);

    /**
     * @notice Emitted when a slot is removed.
     * @param index Removed slot index.
     */
    event RemoveSlot(uint32 indexed index);

    /**
     * @notice Emitted when a slot allocation is reset.
     * @param index Slot index that was reset and removed.
     */
    event ResetAllocation(uint32 indexed index);

    /**
     * @notice Emitted when a slash request is created.
     * @param slashIndex Index of the slash request.
     * @param subnetwork Subnetwork that requested the slash.
     * @param operator Operator subject to the slash request.
     * @param slashAmount Maximum slash amount requested.
     * @param vetoDeadline Timestamp before which the resolver can veto the request.
     */
    event RequestSlash(
        uint256 indexed slashIndex,
        bytes32 indexed subnetwork,
        address indexed operator,
        uint256 slashAmount,
        uint48 vetoDeadline
    );

    /**
     * @notice Emitted when a slash request is executed.
     * @param slashIndex Index of the slash request.
     * @param slashedAmount Amount of collateral slashed.
     */
    event ExecuteSlash(uint256 indexed slashIndex, uint256 slashedAmount);

    /**
     * @notice Emitted when a slash request is vetoed.
     * @param slashIndex Index of the slash request.
     * @param resolver Address of the resolver that vetoed the request.
     */
    event VetoSlash(uint256 indexed slashIndex, address indexed resolver);

    /**
     * @notice Emitted when a resolver is set.
     * @param subnetwork Full identifier of the subnetwork.
     * @param resolver Address of the resolver.
     */
    event SetResolver(bytes32 indexed subnetwork, address resolver);

    /**
     * @notice Emitted when the delegator is initialized.
     * @param params Initialization parameters.
     */
    event Initialize(InitParams params);

    /* FUNCTIONS */

    /**
     * @notice Execute a batch of delegatecalls on the delegator.
     * @param data Calldata items to execute.
     */
    function multicall(bytes[] calldata data) external;

    /**
     * @notice Get the delegator implementation version.
     * @return version Delegator version.
     */
    function VERSION() external view returns (uint64 version);

    /**
     * @notice Get whether burner hook calls are enabled on slashes.
     * @return enabled Whether burner hook calls are enabled.
     */
    function isBurnerHook() external view returns (bool enabled);

    /**
     * @notice Get the veto period duration for slash requests.
     * @return duration Veto period duration.
     */
    function vetoDuration() external view returns (uint48 duration);

    /**
     * @notice Get the resolver update activation delay.
     * @return delay Resolver update delay.
     */
    function resolverSetDelay() external view returns (uint48 delay);

    /**
     * @notice Get pending resolver activation data for a subnetwork.
     * @param subnetwork Full identifier of the subnetwork.
     * @return data Encoded pending resolver address and activation timestamp.
     */
    function pendingResolverData(bytes32 subnetwork) external view returns (bytes32 data);

    /**
     * @notice Get the total number of slots ever created.
     * @return totalSlotCount Total slot count.
     */
    function totalSlots() external view returns (uint32 totalSlotCount);

    /**
     * @notice Get a slot index pending prefix-sum synchronization.
     * @param index Pending sync array index.
     * @return slotIndex Slot index at the pending sync array position.
     */
    function indexesToSync(uint256 index) external view returns (uint32 slotIndex);

    /**
     * @notice Get a slot index's one-based pending sync array position.
     * @param index Slot index.
     * @return toSyncIndex One-based pending sync array position, or zero when the slot is not pending sync.
     */
    function indexToSyncIndex(uint32 index) external view returns (uint32 toSyncIndex);

    /**
     * @notice Get a delayed size by index.
     * @param index Delayed size index.
     * @return delayedSize Delayed size.
     */
    function delayedSizes(uint256 index) external view returns (uint128 delayedSize);

    /**
     * @notice Get slashable stake for a subnetwork/operator at a timestamp and duration.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param duration Duration window.
     * @param timestamp Capture timestamp.
     * @return amount Slashable amount.
     */
    function stakeForAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        external
        view
        returns (uint256 amount);

    /**
     * @notice Get slashable stake for a subnetwork/operator for the current timestamp and duration.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param duration Duration window.
     * @return amount Slashable amount.
     */
    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) external view returns (uint256 amount);

    /**
     * @notice Get slashable stake for a subnetwork/operator at a specific timestamp.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param timestamp Capture timestamp.
     * @return amount Slashable amount.
     */
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes calldata)
        external
        view
        returns (uint256 amount);

    /**
     * @notice Get slashable stake for a subnetwork/operator for the current epoch context.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @return amount Slashable amount.
     */
    function stake(bytes32 subnetwork, address operator) external view returns (uint256 amount);

    /**
     * @notice Get slot metadata for an index.
     * @param index Slot index.
     * @return slot Slot data snapshot.
     */
    function getSlot(uint32 index) external view returns (Slot memory slot);

    /**
     * @notice Get vault balance at a timestamp.
     * @param duration Duration window.
     * @param timestamp Lookup timestamp.
     * @return balance Vault balance.
     */
    function getBalanceAt(uint48 duration, uint48 timestamp) external view returns (uint256 balance);

    /**
     * @notice Get current vault balance.
     * @param duration Duration window.
     * @return balance Vault balance.
     */
    function getBalance(uint48 duration) external view returns (uint256 balance);

    /**
     * @notice Get allocated amount for a slot index at a timestamp.
     * @param index Slot index.
     * @param duration Duration window.
     * @param timestamp Lookup timestamp.
     * @return allocated Allocated amount.
     */
    function getAllocatedAt(uint32 index, uint48 duration, uint48 timestamp) external view returns (uint256 allocated);

    /**
     * @notice Get current allocated amount for a slot index.
     * @param index Slot index.
     * @param duration Duration window.
     * @return allocated Allocated amount.
     */
    function getAllocated(uint32 index, uint48 duration) external view returns (uint256 allocated);

    /**
     * @notice Get assigned slot for a subnetwork/operator at a timestamp.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param timestamp Lookup timestamp.
     * @return index Slot index.
     */
    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp) external view returns (uint32 index);

    /**
     * @notice Get current assigned slot for a subnetwork/operator.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @return index Slot index.
     */
    function getSlotOf(bytes32 subnetwork, address operator) external view returns (uint32 index);

    /**
     * @notice Synchronize delayed slot-size changes and return currently allocated stake.
     * @return allocated Total stake currently allocated across slots, capped by vault balance.
     */
    function totalAllocated() external returns (uint256 allocated);

    /**
     * @notice Get total synced slot size for a subnetwork at a timestamp.
     * @param subnetwork Full identifier of the subnetwork.
     * @param timestamp Lookup timestamp.
     * @return totalSyncedSize Total synced size.
     */
    function getTotalSyncedSizeAt(bytes32 subnetwork, uint48 timestamp) external view returns (uint208 totalSyncedSize);

    /**
     * @notice Get synced slot size for a subnetwork/operator at a timestamp.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @param timestamp Lookup timestamp.
     * @return syncedSize Synced size.
     */
    function getSyncedSizeAt(bytes32 subnetwork, address operator, uint48 timestamp)
        external
        view
        returns (uint128 syncedSize);

    /**
     * @notice Get the total number of slash requests.
     * @return length Slash request count.
     */
    function slashRequestsLength() external view returns (uint256 length);

    /**
     * @notice Get a slash request by index.
     * @param slashIndex Index of the slash request.
     * @return request Slash request data.
     */
    function slashRequests(uint256 slashIndex) external view returns (SlashRequest memory request);

    /**
     * @notice Get the active resolver for a subnetwork.
     * @param subnetwork Full identifier of the subnetwork.
     * @return resolverAddress Active resolver address.
     */
    function resolver(bytes32 subnetwork) external view returns (address resolverAddress);

    /**
     * @notice Get slashable stake at a capture timestamp.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param captureTimestamp Capture timestamp, or zero for the current timestamp.
     * @return amount Slashable amount.
     */
    function slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes calldata)
        external
        view
        returns (uint256 amount);

    /**
     * @notice Create and immediately execute a slash request when no veto blocks execution.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param amount Maximum slash amount.
     * @param captureTimestamp Reserved compatibility argument.
     * @return slashedAmount Amount slashed.
     */
    function slash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes calldata)
        external
        returns (uint256 slashedAmount);

    /**
     * @notice Request a slash for a subnetwork/operator.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param amount Maximum slash amount.
     * @param captureTimestamp Reserved compatibility argument.
     * @return slashIndex Index of the slash request.
     * @dev Only the network middleware can call this function.
     */
    function requestSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes calldata)
        external
        returns (uint256 slashIndex);

    /**
     * @notice Execute a slash request after the veto period has elapsed.
     * @param slashIndex Index of the slash request.
     * @return slashedAmount Amount slashed.
     * @dev Only the network middleware can call this function.
     */
    function executeSlash(uint256 slashIndex, bytes calldata) external returns (uint256 slashedAmount);

    /**
     * @notice Veto a slash request.
     * @param slashIndex Index of the slash request.
     * @dev Only the request resolver can call this function during the veto period.
     */
    function vetoSlash(uint256 slashIndex) external;

    /**
     * @notice Set a resolver for a subnetwork.
     * @param identifier Subnetwork identifier.
     * @param resolver Address of the resolver.
     * @dev Only the network can call this function.
     */
    function setResolver(uint96 identifier, address resolver) external;

    /**
     * @notice Create a new network-operator slot.
     * @param subnetwork Full subnetwork identifier.
     * @param operator Operator address.
     * @param size Initial slot size.
     * @return index Created slot index.
     * @dev Only a CREATE_SLOT_ROLE holder can call this function.
     */
    function createSlot(bytes32 subnetwork, address operator, uint128 size) external returns (uint32 index);

    /**
     * @notice Update slot size.
     * @param index Slot index.
     * @param size New slot size.
     * @dev Only a SET_SIZE_ROLE holder can call this function.
     */
    function setSize(uint32 index, uint128 size) external;

    /**
     * @notice Swap two slots.
     * @param index1 First slot index.
     * @param index2 Second slot index.
     * @dev Only a SWAP_SLOTS_ROLE holder can call this function.
     */
    function swapSlots(uint32 index1, uint32 index2) external;

    /**
     * @notice Remove a slot.
     * @param index Slot index.
     * @dev Only a REMOVE_SLOT_ROLE holder can call this function.
     */
    function removeSlot(uint32 index) external;

    /**
     * @notice Reset allocation for a subnetwork/operator.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @dev Only a network or its middleware can call this function.
     */
    function resetAllocation(bytes32 subnetwork, address operator) external;
}

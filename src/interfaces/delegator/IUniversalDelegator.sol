// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint64 constant UNIVERSAL_DELEGATOR_TYPE = 4;

// Keccak256("CREATE_SLOT_ROLE").
bytes32 constant CREATE_SLOT_ROLE = 0x8aef711962d032b5812b71f6f4353b179696ada38e16233a26a539c32c729007;
// Keccak256("SET_SIZE_ROLE").
bytes32 constant SET_SIZE_ROLE = 0xc9c130a1412d72f4d79081ca47a83fb21e212d7ff57949aadd2c1356e17ee837;
// Keccak256("SWAP_SLOTS_ROLE").
bytes32 constant SWAP_SLOTS_ROLE = 0xffd98ac79bb60993f79efa77ec34b3f446950a5c284ae3036fc0fb810a00af60;
// Keccak256("REMOVE_SLOT_ROLE").
bytes32 constant REMOVE_SLOT_ROLE = 0x1cbee842b8b18f1dea4a0fb8117bb405b26bede02a0f7f47acb5d727ef90e6f4;
// Keccak256("SET_WITHDRAWAL_BUFFER_SIZE_ROLE").
bytes32 constant SET_WITHDRAWAL_BUFFER_SIZE_ROLE = 0x6f48b129515ad8dd335666ffdfdf6533e7a5a9a9cd01b8a62f938f739fc9a4ce;

uint32 constant WITHDRAWAL_BUFFER_CHILD_INDEX = 0xFFFFFFFF;
uint64 constant WITHDRAWAL_BUFFER_INDEX = uint64(WITHDRAWAL_BUFFER_CHILD_INDEX) << 32;
uint256 constant MAX_NETWORKS = 15;
uint256 constant MAX_OPERATORS = 20;

/**
 * @title IUniversalDelegator
 * @notice Interface for the UniversalDelegator contract.
 */
interface IUniversalDelegator {
    /* ERRORS */

    /**
     * @notice Raised when a network or operator is already assigned to a slot.
     */
    error AlreadyAssigned();

    /**
     * @notice Raised when a maximum network limit is already set.
     */
    error AlreadySet();

    /**
     * @notice Raised when the provided subnetwork or operator is zero.
     */
    error InvalidNetOrOp();

    /**
     * @notice Raised when the provided maximum network limit is not 2^256-1.
     */
    error LimitNotUint256Max();

    /**
     * @notice Raised when no slot is assigned for the requested subject.
     */
    error NotAssigned();

    /**
     * @notice Raised when there is not enough balance for the operation.
     */
    error NotEnoughBalance();

    /**
     * @notice Raised when migration functions are called outside migration mode.
     */
    error NotMigrating();

    /**
     * @notice Raised when the caller is not a registered network.
     */
    error NotNetwork();

    /**
     * @notice Raised when the caller is neither a network nor its middleware.
     */
    error NotNetworkOrMiddleware();

    /**
     * @notice Raised when two slots are not in the same allocation state.
     */
    error NotSameAllocated();

    /**
     * @notice Raised when two slots do not have the same parent.
     */
    error NotSameParent();

    /**
     * @notice Raised when the caller is not the vault slasher.
     */
    error NotSlasher();

    /**
     * @notice Raised when the provided vault is invalid.
     */
    error NotVault();

    /**
     * @notice Raised when the connected vault version is older than required.
     */
    error OldVault();

    /**
     * @notice Raised when a slot is only partially allocated and cannot be moved.
     */
    error PartiallyAllocated();

    /**
     * @notice Raised when trying to remove a slot that still has allocation.
     */
    error SlotAllocated();

    /**
     * @notice Raised when the requested slot does not exist.
     */
    error SlotNotExists();

    /**
     * @notice Raised when the maximum number of children for a slot is exceeded.
     */
    error TooManyChildren();

    /**
     * @notice Raised when a slot operation is attempted at an invalid hierarchy depth.
     */
    error WrongDepth();

    /**
     * @notice Raised when slot ordering constraints are violated.
     */
    error WrongOrder();

    /* STRUCTS */

    /**
     * @notice Slot snapshot data.
     * @param exists Whether the slot exists.
     * @param operator Operator assigned to the slot.
     * @param subnetwork Subnetwork assigned to the slot.
     * @param size Latest synced slot size checkpoint value.
     * @param delayedTimestamp Timestamp when the delayed size becomes effective, or zero when there is no delay.
     * @param delayedSize Delayed target size, or zero when there is no delay.
     */
    struct Slot {
        bool exists;
        address operator;
        bytes32 subnetwork;
        uint128 size;
        uint48 delayedTimestamp;
        uint128 delayedSize;
    }

    /**
     * @notice Initialization parameters for the universal delegator.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param createSlotRoleHolder Address of the initial CREATE_SLOT_ROLE holder.
     * @param setSizeRoleHolder Address of the initial SET_SIZE_ROLE holder.
     * @param swapSlotsRoleHolder Address of the initial SWAP_SLOTS_ROLE holder.
     * @param removeSlotRoleHolder Address of the initial REMOVE_SLOT_ROLE holder.
     * @param setWithdrawalBufferSizeRoleHolder Deprecated.
     * @param withdrawalBufferSize Deprecated.
     */
    struct InitParams {
        address defaultAdminRoleHolder;
        address createSlotRoleHolder;
        address setSizeRoleHolder;
        address swapSlotsRoleHolder;
        address removeSlotRoleHolder;
        address setWithdrawalBufferSizeRoleHolder;
        uint128 withdrawalBufferSize;
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
     * @notice Emitted when two sibling slots are swapped.
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
     * @notice Emitted when slash accounting is applied to a slot.
     * @param index Slot index whose size was reduced.
     * @param amount Slash amount applied to slot accounting.
     */
    event OnSlash(uint32 indexed index, uint256 amount);

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
     * @notice Get the associated vault address.
     * @return vaultAddress Address of the vault.
     */
    function vault() external view returns (address vaultAddress);

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
    function getSlot(uint64 index) external view returns (Slot memory slot);

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
     * @notice Get configured withdrawal buffer size.
     * @return withdrawalBuffer Current withdrawal buffer size.
     */
    function getWithdrawalBuffer() external view returns (uint256 withdrawalBuffer);

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
     * @notice Get the timestamp when migration occurred.
     * @return migrateTimestamp Timestamp when migration occurred.
     */
    function migrateTimestamp() external view returns (uint48 migrateTimestamp);

    /**
     * @notice Get the address of the previous delegator before migration.
     * @return oldDelegator Address of the previous delegator before migration.
     */
    function oldDelegator() external view returns (address oldDelegator);

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
     * @notice Reset allocation for a subnetwork.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @dev Only a network or its middleware can call this function.
     *      Warning: this functions resets all the pending slash requests, too.
     */
    function resetAllocation(bytes32 subnetwork, address operator) external;

    /**
     * @notice Apply a slash to the current slot assigned to a subnetwork/operator.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @param amount Slash amount.
     * @dev Only the vault slasher can call this function.
     */
    function onSlash(bytes32 subnetwork, address operator, uint256 amount) external;

    /**
     * @notice Apply a slash to the migrated slot assigned to a subnetwork/operator.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @param amount Slash amount.
     * @dev Only the vault slasher can call this function.
     */
    function onSlashLegacy(bytes32 subnetwork, address operator, uint256 amount) external;

    /**
     * @notice Record the previous delegator used before migration.
     * @param oldDelegator_ Previous delegator address.
     * @dev Only the vault can call this function.
     */
    function migrate(address oldDelegator_) external;
}

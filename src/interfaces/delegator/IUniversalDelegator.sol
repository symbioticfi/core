// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint64 constant UNIVERSAL_DELEGATOR_TYPE = 4;

uint32 constant WITHDRAWAL_BUFFER_CHILD_INDEX = 0xFFFFFFFF;
uint96 constant WITHDRAWAL_BUFFER_INDEX = 0xFFFFFFFF0000000000000000;

// Keccak256("HOOK_SET_ROLE").
bytes32 constant HOOK_SET_ROLE = 0xd1c1f6fa6bf27d54c5e54c7c1dc6e5004d3c027ea1994fe68b29c1b51b69c36c;

uint256 constant HOOK_GAS_LIMIT = 250_000;
uint256 constant HOOK_RESERVE = 20_000;

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

uint256 constant MAX_GROUPS = 10;
uint256 constant MAX_NETWORKS = 15;
uint256 constant MAX_OPERATORS = 20;

/**
 * @title IUniversalDelegator
 * @notice Interface for the UniversalDelegator contract.
 */
interface IUniversalDelegator {
    /* ERRORS */

    /**
     * @notice Raised when there is not enough available stake for the operation.
     */
    error NotEnoughAvailable();

    /**
     * @notice Raised when the caller is not a registered network.
     */
    error NotNetwork();

    /**
     * @notice Raised when the caller is not the vault slasher.
     */
    error NotSlasher();

    /**
     * @notice Raised when the provided vault is invalid.
     */
    error NotVault();

    /**
     * @notice Raised when two slots do not have the same parent.
     */
    error NotSameParent();

    /**
     * @notice Raised when two slots are not in the same allocation state.
     */
    error NotSameAllocated();

    /**
     * @notice Raised when a slot is only partially allocated and cannot be moved.
     */
    error PartiallyAllocated();

    /**
     * @notice Raised when no slot is assigned for the requested subject.
     */
    error NotAssigned();

    /**
     * @notice Raised when trying to remove a slot that still has allocation.
     */
    error SlotAllocated();

    /**
     * @notice Raised when a slot operation is attempted at an invalid hierarchy depth.
     */
    error WrongDepth();

    /**
     * @notice Raised when an operation is incompatible with shared mode.
     */
    error IsShared();

    /**
     * @notice Raised when the requested slot does not exist.
     */
    error SlotNotCreated();

    /**
     * @notice Raised when the connected vault version is older than required.
     */
    error OldVault();

    /**
     * @notice Raised when migration functions are called outside migration mode.
     */
    error NotMigrating();

    /**
     * @notice Raised when the caller is neither a network nor its middleware.
     */
    error NotNetworkOrMiddleware();

    /**
     * @notice Raised when a network or operator is already assigned to a slot.
     */
    error AlreadyAssigned();

    /**
     * @notice Raised when there is not enough gas for the hook call.
     */
    error InsufficientHookGas();

    /**
     * @notice Raised when requested no-plugins capacity exceeds available amount.
     */
    error NotEnoughNoPlugins();

    /**
     * @notice Raised when slot ordering constraints are violated.
     */
    error WrongOrder();

    /**
     * @notice Raised when the maximum number of children for a slot is exceeded.
     */
    error TooManyChildren();

    /* STRUCTS */

    /**
     * @notice Slot snapshot data.
     * @param exists Whether the slot exists.
     * @param nextSlot Next sibling child index.
     * @param prevSlot Previous sibling child index.
     * @param totalChildren Total number of children ever created.
     * @param existChildren Number of currently existing children.
     * @param firstChild First child index.
     * @param lastChild Last child index.
     * @param isShared Whether slot allocation is shared among children.
     * @param noPlugins Whether slot stake must stay outside plugins.
     * @param size Slot size value.
     * @param prevSum Prefix sum of previous sibling sizes.
     */
    struct Slot {
        bool exists;
        uint32 nextSlot;
        uint32 prevSlot;
        uint32 totalChildren;
        uint32 existChildren;
        uint32 firstChild;
        uint32 lastChild;
        bool isShared;
        bool noPlugins;
        uint128 size;
        uint208 prevSum;
    }

    /**
     * @notice Initialization parameters for the universal delegator.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param hook Address of the hook contract.
     * @param hookSetRoleHolder Address of the initial HOOK_SET_ROLE holder.
     * @param createSlotRoleHolder Address of the initial CREATE_SLOT_ROLE holder.
     * @param setSizeRoleHolder Address of the initial SET_SIZE_ROLE holder.
     * @param swapSlotsRoleHolder Address of the initial SWAP_SLOTS_ROLE holder.
     * @param withdrawalBufferSize Initial withdrawal buffer size.
     */
    struct InitParams {
        address defaultAdminRoleHolder;
        address hook;
        address hookSetRoleHolder;
        address createSlotRoleHolder;
        address setSizeRoleHolder;
        address swapSlotsRoleHolder;
        uint128 withdrawalBufferSize;
    }

    /**
     * @notice Base parameters needed for delegators' deployment.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param hook Address of the hook contract.
     * @param hookSetRoleHolder Address of the initial HOOK_SET_ROLE holder.
     */
    struct BaseParams {
        address defaultAdminRoleHolder;
        address hook;
        address hookSetRoleHolder;
    }

    /* EVENTS */

    /**
     * @notice Emitted when a slot is created.
     * @param index Index of the created slot.
     * @param isShared Whether the slot is shared.
     * @param noPlugins Whether the slot is marked as no-plugins.
     * @param size Initial slot size.
     */
    event CreateSlot(uint96 indexed index, bool isShared, bool noPlugins, uint128 size);

    /**
     * @notice Emitted when a slot size is updated.
     * @param index Slot index.
     * @param size New slot size.
     */
    event SetSize(uint96 indexed index, uint128 size);

    /**
     * @notice Emitted when two sibling slots are swapped.
     * @param index1 First slot index.
     * @param index2 Second slot index.
     */
    event SwapSlots(uint96 indexed index1, uint96 indexed index2);

    /**
     * @notice Emitted when a slot is removed.
     * @param index Removed slot index.
     */
    event RemoveSlot(uint96 indexed index);

    /**
     * @notice Emitted when a subnetwork allocation is reset.
     * @param index Slot index that was reset.
     * @param subnetwork Full subnetwork identifier.
     */
    event ResetAllocation(uint96 indexed index, bytes32 indexed subnetwork);

    /**
     * @notice Emitted when withdrawal buffer size is updated.
     * @param newWithdrawalBufferSize New withdrawal buffer size.
     */
    event SetWithdrawalBufferSize(uint128 newWithdrawalBufferSize);

    /**
     * @notice Emitted when a hook is set.
     * @param hook Address of the hook.
     */
    event SetHook(address indexed hook);

    /**
     * @notice Emitted when a slash is applied.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param amount Slashed amount.
     */
    event OnSlash(bytes32 indexed subnetwork, address indexed operator, uint256 amount);

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
     * @notice Get the hook contract address.
     * @return hookAddress Address of the hook contract.
     */
    function hook() external view returns (address hookAddress);

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
     * @param hints Encoded lookup hints.
     * @return amount Slashable amount.
     */
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
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
    function getSlot(uint96 index) external view returns (Slot memory slot);

    /**
     * @notice Get children pending amount at a timestamp.
     * @param index Parent slot index.
     * @param duration Duration window.
     * @param timestamp Lookup timestamp.
     * @return pending Children pending amount.
     */
    function getChildrenPendingAt(uint96 index, uint48 duration, uint48 timestamp)
        external
        view
        returns (uint208 pending);

    /**
     * @notice Get current children pending amount.
     * @param index Parent slot index.
     * @param duration Duration window.
     * @return pending Children pending amount.
     */
    function getChildrenPending(uint96 index, uint48 duration) external view returns (uint208 pending);

    /**
     * @notice Get slot pending amount at a timestamp.
     * @param index Slot index.
     * @param duration Duration window.
     * @param timestamp Lookup timestamp.
     * @return pending Slot pending amount.
     */
    function getPendingAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint208 pending);

    /**
     * @notice Get current slot pending amount.
     * @param index Slot index.
     * @param duration Duration window.
     * @return pending Slot pending amount.
     */
    function getPending(uint96 index, uint48 duration) external view returns (uint208 pending);

    /**
     * @notice Get slot balance at a timestamp.
     * @param index Slot index.
     * @param duration Duration window.
     * @param timestamp Lookup timestamp.
     * @return balance Slot balance.
     */
    function getBalanceAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint256 balance);

    /**
     * @notice Get current slot balance.
     * @param index Slot index.
     * @param duration Duration window.
     * @return balance Slot balance.
     */
    function getBalance(uint96 index, uint48 duration) external view returns (uint256 balance);

    /**
     * @notice Get available slot balance at a timestamp.
     * @param index Slot index.
     * @param duration Duration window.
     * @param timestamp Lookup timestamp.
     * @return available Available balance.
     */
    function getAvailableAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint256 available);

    /**
     * @notice Get current available slot balance.
     * @param index Slot index.
     * @param duration Duration window.
     * @return available Available balance.
     */
    function getAvailable(uint96 index, uint48 duration) external view returns (uint256 available);

    /**
     * @notice Get allocated amount for a slot index at a timestamp.
     * @param index Slot index.
     * @param duration Duration window.
     * @param timestamp Lookup timestamp.
     * @return allocated Allocated amount.
     */
    function getAllocatedAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint256 allocated);

    /**
     * @notice Get current allocated amount for a slot index.
     * @param index Slot index.
     * @param duration Duration window.
     * @return allocated Allocated amount.
     */
    function getAllocated(uint96 index, uint48 duration) external view returns (uint256 allocated);

    /**
     * @notice Get allocated amount for a subnetwork/operator at a timestamp.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param duration Duration window.
     * @param timestamp Lookup timestamp.
     * @return allocated Allocated amount.
     */
    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        external
        view
        returns (uint256 allocated);

    /**
     * @notice Get current allocated amount for a subnetwork/operator.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param duration Duration window.
     * @return allocated Allocated amount.
     */
    function getAllocated(bytes32 subnetwork, address operator, uint48 duration)
        external
        view
        returns (uint256 allocated);

    /**
     * @notice Get filled amount at a timestamp.
     * @param index Slot index.
     * @param duration Duration window.
     * @param timestamp Lookup timestamp.
     * @return filled Filled amount.
     */
    function getFilledAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint256 filled);

    /**
     * @notice Get current filled amount.
     * @param index Slot index.
     * @param duration Duration window.
     * @return filled Filled amount.
     */
    function getFilled(uint96 index, uint48 duration) external view returns (uint256 filled);

    /**
     * @notice Get assigned slot of a network at a timestamp.
     * @param subnetwork Full identifier of the subnetwork.
     * @param timestamp Lookup timestamp.
     * @return index Slot index.
     */
    function getSlotOfNetworkAt(bytes32 subnetwork, uint48 timestamp) external view returns (uint96 index);

    /**
     * @notice Get current assigned slot of a network.
     * @param subnetwork Full identifier of the subnetwork.
     * @return index Slot index.
     */
    function getSlotOfNetwork(bytes32 subnetwork) external view returns (uint96 index);

    /**
     * @notice Get assigned operator slot at a timestamp.
     * @param parentIndex Parent slot index.
     * @param operator Address of the operator.
     * @param timestamp Lookup timestamp.
     * @return index Slot index.
     */
    function getSlotOfOperatorAt(uint96 parentIndex, address operator, uint48 timestamp)
        external
        view
        returns (uint96 index);

    /**
     * @notice Get current assigned operator slot.
     * @param parentIndex Parent slot index.
     * @param operator Address of the operator.
     * @return index Slot index.
     */
    function getSlotOfOperator(uint96 parentIndex, address operator) external view returns (uint96 index);

    /**
     * @notice Get assigned slot for a subnetwork/operator at a timestamp.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param timestamp Lookup timestamp.
     * @return index Slot index.
     */
    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp) external view returns (uint96 index);

    /**
     * @notice Get current assigned slot for a subnetwork/operator.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @return index Slot index.
     */
    function getSlotOf(bytes32 subnetwork, address operator) external view returns (uint96 index);

    /**
     * @notice Check whether a subnetwork is assigned to a shared slot.
     * @param subnetwork Full identifier of the subnetwork.
     * @return isShared Whether the slot is shared.
     */
    function getIsShared(bytes32 subnetwork) external view returns (bool isShared);

    /**
     * @notice Check whether a subnetwork is assigned to a no-plugins slot.
     * @param subnetwork Full identifier of the subnetwork.
     * @return isNoPlugins Whether the slot is marked as no-plugins.
     */
    function getIsNoPlugins(bytes32 subnetwork) external view returns (bool isNoPlugins);

    /**
     * @notice Get total no-plugins size across root slots.
     * @return noPluginsSize Total no-plugins size.
     */
    function getNoPluginsSize() external view returns (uint256 noPluginsSize);

    /**
     * @notice Get configured withdrawal buffer size.
     * @return withdrawalBuffer Current withdrawal buffer size.
     */
    function getWithdrawalBuffer() external view returns (uint256 withdrawalBuffer);

    /**
     * @notice Create a new slot under a parent.
     * @param subnetworkOrOperator Encoded subnetwork or operator identifier.
     * @param parentIndex Parent slot index.
     * @param isShared Whether the new slot is shared.
     * @param noPlugins Whether the new slot is no-plugins.
     * @param size Initial slot size.
     * @return index Created slot index.
     * @dev Only a CREATE_SLOT_ROLE holder can call this function.
     */
    function createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noPlugins, uint128 size)
        external
        returns (uint96 index);

    /**
     * @notice Update slot size.
     * @param index Slot index.
     * @param size New slot size.
     * @return pending Newly created pending amount.
     * @dev Only a SET_SIZE_ROLE holder can call this function.
     */
    function setSize(uint96 index, uint128 size) external returns (uint208 pending);

    /**
     * @notice Swap two sibling slots.
     * @param index1 First slot index.
     * @param index2 Second slot index.
     * @dev Only a SWAP_SLOTS_ROLE holder can call this function.
     */
    function swapSlots(uint96 index1, uint96 index2) external;

    /**
     * @notice Remove a slot.
     * @param index Slot index.
     * @dev Only a REMOVE_SLOT_ROLE holder can call this function.
     */
    function removeSlot(uint96 index) external;

    /**
     * @notice Reset allocation for a subnetwork.
     * @param subnetwork Full identifier of the subnetwork.
     * @dev Only a network or its middleware can call this function.
     */
    function resetAllocation(bytes32 subnetwork) external;

    /**
     * @notice Update withdrawal buffer size.
     * @param newWithdrawalBufferSize New withdrawal buffer size.
     * @dev Only a SET_WITHDRAWAL_BUFFER_SIZE_ROLE holder can call this function.
     */
    function setWithdrawalBufferSize(uint128 newWithdrawalBufferSize) external;

    /**
     * @notice Set a new hook.
     * @param hook Address of the hook.
     * @dev Only a HOOK_SET_ROLE holder can call this function.
     */
    function setHook(address hook) external;

    /**
     * @notice Get the legacy maximum limit value for a subnetwork.
     * @param subnetwork Full identifier of the subnetwork.
     * @return limit Maximum possible uint256 value.
     * @dev This function is deprecated and always returns type(uint256).max.
     */
    function maxNetworkLimit(bytes32 subnetwork) external pure returns (uint256 limit);

    /**
     * @notice Set the maximum limit for a subnetwork.
     * @param identifier Subnetwork identifier.
     * @param amount New maximum limit.
     * @dev This function is deprecated and performs no action.
     */
    function setMaxNetworkLimit(uint96 identifier, uint256 amount) external;
}

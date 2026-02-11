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

    error NotEnoughAvailable();
    error NotNetwork();
    error NotSlasher();
    error NotVault();
    error NotSameParent();
    error NotSameAllocated();
    error PartiallyAllocated();
    error NotAssigned();
    error SlotAllocated();
    error WrongDepth();
    error IsShared();
    error SlotNotCreated();
    error OldVault();
    error NotMigrating();
    error WrongMigrate();
    error NotNetworkOrMiddleware();
    error AlreadyAssigned();
    error InsufficientHookGas();
    error NotEnoughNoPlugins();
    error WrongOrder();
    error TooManyChildren();

    /* STRUCTS */

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

    struct InitParams {
        address defaultAdminRoleHolder;
        address hook;
        address hookSetRoleHolder;
        address createSlotRoleHolder;
        address setIsSharedRoleHolder;
        address setSizeRoleHolder;
        address setShareRoleHolder;
        address swapSlotsRoleHolder;
        uint128 withdrawalBufferSize;
    }

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

    /* EVENTS */

    event CreateSlot(uint96 indexed index, bool isShared, bool noPlugins, uint128 size);

    /**
     * @notice Emitted when a slash happens.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param amount Amount of the collateral to be slashed.
     */
    event OnSlash(bytes32 indexed subnetwork, address indexed operator, uint256 amount);

    /**
     * @notice Emitted when a hook is set.
     * @param hook Address of the hook.
     */
    event SetHook(address indexed hook);

    event SetSize(uint96 indexed index, uint128 size);

    event SwapSlots(uint96 indexed index1, uint96 indexed index2);

    event RemoveSlot(uint96 indexed index);

    event ResetAllocation(uint96 indexed index, bytes32 indexed subnetwork);

    event SetWithdrawalBufferSize(uint128 newWithdrawalBufferSize);

    event Initialize(InitParams params);

    /* FUNCTIONS */

    /**
     * @notice Execute a batch of delegatecalls on the delegator.
     * @param data Calldata items to execute.
     */
    function multicall(bytes[] calldata data) external;

    /**
     * @notice Get a version of the delegator (different versions mean different interfaces).
     * @return Version Of the delegator.
     * @dev Must return 1 for this one.
     */
    function VERSION() external view returns (uint64);

    /**
     * @notice Get the vault's address.
     * @return Address Of the vault.
     */
    function vault() external view returns (address);

    /**
     * @notice Get the hook's address.
     * @return Address Of the hook.
     * @dev The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.
     */
    function hook() external view returns (address);

    /**
     * @notice Get a particular subnetwork's maximum limit (meaning the subnetwork is not ready to get more as a stake).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @return Maximum Limit of the subnetwork.
     */
    function maxNetworkLimit(bytes32 subnetwork) external pure returns (uint256);

    /**
     * @notice Get a stake that a given subnetwork could be able to slash for a certain operator at a given timestamp until the end of the consequent epoch using hints (if no cross-slashing and no slashings by the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param timestamp Time point to capture the stake at.
     * @param hints Hints for the checkpoints' indexes.
     * @return Slashable Stake at the given timestamp until the end of the consequent epoch.
     * @dev Warning: it is not safe to use timestamp >= current one for the stake capturing, as it can change later.
     */
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        external
        view
        returns (uint256);

    /**
     * @notice Get a stake that a given subnetwork will be able to slash for a certain operator until the end of the next epoch (if no cross-slashing and no slashings by the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @return Slashable Stake until the end of the next epoch.
     * @dev Warning: this function is not safe to use for stake capturing, as it can change by the end of the block.
     */
    function stake(bytes32 subnetwork, address operator) external view returns (uint256);

    /**
     * @notice Set a maximum limit for a subnetwork (how much stake the subnetwork is ready to get).
     * @param identifier Identifier of the subnetwork.
     * @param amount New maximum subnetwork's limit.
     * @dev Only a network can call this function.
     */
    function setMaxNetworkLimit(uint96 identifier, uint256 amount) external;

    /**
     * @notice Set a new hook.
     * @param hook Address of the hook.
     * @dev Only a HOOK_SET_ROLE holder can call this function.
     * The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.
     */
    function setHook(address hook) external;

    function getWithdrawalBuffer() external view returns (uint256);

    function getNoPluginsSize() external view returns (uint256);

    function getSlot(uint96 index) external view returns (Slot memory);

    function getChildrenPendingAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint208);

    function getChildrenPending(uint96 index, uint48 duration) external view returns (uint208);

    function getPendingAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint208);

    function getPending(uint96 index, uint48 duration) external view returns (uint208);

    function stakeForAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        external
        view
        returns (uint256);

    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) external view returns (uint256);

    function getBalanceAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint256);

    function getBalance(uint96 index, uint48 duration) external view returns (uint256);

    function getAvailableAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint256);

    function getAvailable(uint96 index, uint48 duration) external view returns (uint256);

    function getAllocatedAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint256);

    function getAllocated(uint96 index, uint48 duration) external view returns (uint256);

    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        external
        view
        returns (uint256);

    function getAllocated(bytes32 subnetwork, address operator, uint48 duration) external view returns (uint256);

    function getFilledAt(uint96 index, uint48 duration, uint48 timestamp) external view returns (uint256);

    function getFilled(uint96 index, uint48 duration) external view returns (uint256);

    function getSlotOfNetworkAt(bytes32 subnetwork, uint48 timestamp) external view returns (uint96);

    function getSlotOfNetwork(bytes32 subnetwork) external view returns (uint96);

    function getSlotOfOperatorAt(uint96 parentIndex, address operator, uint48 timestamp) external view returns (uint96);

    function getSlotOfOperator(uint96 parentIndex, address operator) external view returns (uint96);

    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp) external view returns (uint96);

    function getSlotOf(bytes32 subnetwork, address operator) external view returns (uint96);

    function getIsShared(bytes32 subnetwork) external view returns (bool);

    function getIsNoPlugins(bytes32 subnetwork) external view returns (bool);

    function createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noPlugins, uint128 size)
        external
        returns (uint96 index);

    function setSize(uint96 index, uint128 size) external returns (uint208 pending);

    function swapSlots(uint96 index1, uint96 index2) external;

    function removeSlot(uint96 index) external;

    function resetAllocation(bytes32 subnetwork) external;

    function setWithdrawalBufferSize(uint128 newWithdrawalBufferSize) external;
}

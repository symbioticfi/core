// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Checkpoints} from "../../contracts/libraries/CheckpointsV2.sol";

uint32 constant WITHDRAWAL_BUFFER_CHILD_INDEX = 0xFFFFFFFF;
uint96 constant WITHDRAWAL_BUFFER_INDEX = 0xFFFFFFFF0000000000000000;

// keccak256("HOOK_SET_ROLE")
bytes32 constant HOOK_SET_ROLE = 0xd1c1f6fa6bf27d54c5e54c7c1dc6e5004d3c027ea1994fe68b29c1b51b69c36c;

uint256 constant HOOK_GAS_LIMIT = 250_000;
uint256 constant HOOK_RESERVE = 20_000;

// keccak256("CREATE_SLOT_ROLE")
bytes32 constant CREATE_SLOT_ROLE = 0x8aef711962d032b5812b71f6f4353b179696ada38e16233a26a539c32c729007;
// keccak256("SET_SIZE_ROLE")
bytes32 constant SET_SIZE_ROLE = 0xc9c130a1412d72f4d79081ca47a83fb21e212d7ff57949aadd2c1356e17ee837;
// keccak256("SWAP_SLOTS_ROLE")
bytes32 constant SWAP_SLOTS_ROLE = 0xffd98ac79bb60993f79efa77ec34b3f446950a5c284ae3036fc0fb810a00af60;
// keccak256("REMOVE_SLOT_ROLE")
bytes32 constant REMOVE_SLOT_ROLE = 0x1cbee842b8b18f1dea4a0fb8117bb405b26bede02a0f7f47acb5d727ef90e6f4;

uint256 constant MAX_GROUPS = 10;
uint256 constant MAX_NETWORKS = 15;
uint256 constant MAX_OPERATORS = 20;

/**
 * @title IVault
 * @dev Deprecated functions:
 *      maxNetworkLimit()
 *      setMaxNetworkLimit()
 * @dev Removed functions (due to internal-only usage):
 *      onSlash()
 */
interface IUniversalDelegator {
    error AlreadySet();
    error NotEnoughAvailable();
    error NotNetwork();
    error NotSlasher();
    error NotVault();
    error NotSameParent();
    error SameSlot();
    error NotSameAllocated();
    error PartiallyAllocated();
    error NotAssigned();
    error SlotAllocated();
    error MissingRoleHolders();
    error IsSharedNotChanged();
    error WrongDepth();
    error TooManyShares();
    error IsShared();
    error SlotNotCreated();
    error OldVault();
    error NotMigrating();
    error WrongMigrate();
    error InvalidDuration();
    error IsWithdrawalBuffer();
    error NotNetworkOrMiddleware();
    error AlreadyAssigned();
    error InsufficientHookGas();
    error TooManyOperators();
    error NotEnoughNoPlugins();
    error SlotNotAllocated();
    error WrongOrder();
    error TooManyChildren();

    /**
     * @notice Base parameters needed for delegators' deployment.
     * @param defaultAdminRoleHolder address of the initial DEFAULT_ADMIN_ROLE holder
     * @param hook address of the hook contract
     * @param hookSetRoleHolder address of the initial HOOK_SET_ROLE holder
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
    }

    struct Slot {
        bool exists;
        uint32 nextSlot;
        uint32 prevSlot;
        uint32 numChildren;
        uint32 firstChild;
        uint32 lastChild;
        bool isShared;
        bool noPlugins;
        uint128 size;
        uint208 prevSum;
        uint208 childrenPendingCumulative;
    }

    event CreateSlot(uint96 indexed index, bool isShared, bool noPlugins, uint128 size);

    /**
     * @notice Emitted when a slash happens.
     * @param subnetwork full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)
     * @param operator address of the operator
     * @param amount amount of the collateral to be slashed
     */
    event OnSlash(bytes32 indexed subnetwork, address indexed operator, uint256 amount);

    /**
     * @notice Emitted when a hook is set.
     * @param hook address of the hook
     */
    event SetHook(address indexed hook);

    event SetIsShared(uint96 indexed index, bool isShared);

    event SetSize(uint96 indexed index, uint128 size);

    event SwapSlots(uint96 indexed index1, uint96 indexed index2);

    event RemoveSlot(uint96 indexed index);

    event ResetAllocation(uint96 indexed index, bytes32 indexed subnetwork);

    event Initialize(InitParams params);

    /**
     * @notice Get a version of the delegator (different versions mean different interfaces).
     * @return version of the delegator
     * @dev Must return 1 for this one.
     */
    function VERSION() external view returns (uint64);

    /**
     * @notice Get the vault's address.
     * @return address of the vault
     */
    function vault() external view returns (address);

    /**
     * @notice Get the hook's address.
     * @return address of the hook
     * @dev The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.
     */
    function hook() external view returns (address);

    /**
     * @notice Get a particular subnetwork's maximum limit
     *         (meaning the subnetwork is not ready to get more as a stake).
     * @param subnetwork full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)
     * @return maximum limit of the subnetwork
     */
    function maxNetworkLimit(bytes32 subnetwork) external pure returns (uint256);

    /**
     * @notice Get a stake that a given subnetwork could be able to slash for a certain operator at a given timestamp
     *         until the end of the consequent epoch using hints (if no cross-slashing and no slashings by the subnetwork).
     * @param subnetwork full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)
     * @param operator address of the operator
     * @param timestamp time point to capture the stake at
     * @param hints hints for the checkpoints' indexes
     * @return slashable stake at the given timestamp until the end of the consequent epoch
     * @dev Warning: it is not safe to use timestamp >= current one for the stake capturing, as it can change later.
     */
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        external
        view
        returns (uint256);

    /**
     * @notice Get a stake that a given subnetwork will be able to slash
     *         for a certain operator until the end of the next epoch (if no cross-slashing and no slashings by the subnetwork).
     * @param subnetwork full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)
     * @param operator address of the operator
     * @return slashable stake until the end of the next epoch
     * @dev Warning: this function is not safe to use for stake capturing, as it can change by the end of the block.
     */
    function stake(bytes32 subnetwork, address operator) external view returns (uint256);

    /**
     * @notice Set a maximum limit for a subnetwork (how much stake the subnetwork is ready to get).
     * identifier identifier of the subnetwork
     * @param amount new maximum subnetwork's limit
     * @dev Only a network can call this function.
     */
    function setMaxNetworkLimit(uint96 identifier, uint256 amount) external;

    /**
     * @notice Set a new hook.
     * @param hook address of the hook
     * @dev Only a HOOK_SET_ROLE holder can call this function.
     *      The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.
     */
    function setHook(address hook) external;

    function getWithdrawalBuffer() external view returns (uint256);

    function getNoPluginsSize() external view returns (uint208);

    function getSlot(uint96 index) external view returns (Slot memory);

    function stakeForAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp)
        external
        view
        returns (uint256);

    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) external view returns (uint256);

    function getBalanceAt(uint96 index, uint48 timestamp, uint48 duration) external view returns (uint256);

    function getBalance(uint96 index, uint48 duration) external view returns (uint256);

    function getAvailableAt(uint96 index, uint48 timestamp, uint48 duration) external view returns (uint256);

    function getAvailable(uint96 index, uint48 duration) external view returns (uint256);

    function getAllocatedAt(uint96 index, uint48 timestamp, uint48 duration) external view returns (uint256);

    function getAllocated(uint96 index, uint48 duration) external view returns (uint256);

    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 timestamp, uint48 duration)
        external
        view
        returns (uint256);

    function getAllocated(bytes32 subnetwork, address operator, uint48 duration) external view returns (uint256);

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
}

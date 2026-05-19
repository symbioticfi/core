// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDelegator} from "./IDelegator.sol";

uint64 constant ALLOCATIONS_DELEGATOR_TYPE = 5;

uint256 constant LIMIT_SHARE_SCALE = 1e18;

// Keccak256("SET_ADAPTER_LIMITS_ROLE").
bytes32 constant SET_ADAPTER_LIMITS_ROLE = 0x8c729dc4be31fd24714d9aa5498f0c485d31935b8850fc1f2d8fce2bfa1f0e35;
// Keccak256("SWAP_ADAPTERS_ROLE").
bytes32 constant SWAP_ADAPTERS_ROLE = 0x1d53409af49f741b77991b0584075fbe3113d2af2e558244c183033fd9dd74ce;
// Keccak256("ALLOCATE_ROLE").
bytes32 constant ALLOCATE_ROLE = 0x3e716b9e768f9140a805a7bd2ea8ed6273ee028841754af21433cf2650718e90;
// Keccak256("DEALLOCATE_ROLE").
bytes32 constant DEALLOCATE_ROLE = 0x6fc880ed9b763496bee1eacc1616a9bd7192cd16545c429802620efc6999dcda;

/**
 * @title IAllocationsDelegator
 * @notice Interface for the simple adapter allocations delegator.
 */
interface IAllocationsDelegator is IDelegator {
    /* ERRORS */

    /**
     * @notice Raised when adapter arrays have inconsistent lengths.
     */
    error InvalidLength();

    /**
     * @notice Raised when an adapter address is invalid.
     */
    error InvalidAdapter();

    /**
     * @notice Raised when a share limit is above LIMIT_SHARE_SCALE.
     */
    error InvalidShareLimit();

    /**
     * @notice Raised when an adapter has no allocation above its configured limit.
     */
    error AdapterNotOverLimit();

    /**
     * @notice Raised when the connected vault version is older than required.
     */
    error OldVault();

    /**
     * @notice Raised when the caller is not the associated vault.
     */
    error NotVault();

    /**
     * @notice Raised when the vault does not have enough liquid collateral after deallocation.
     */
    error InsufficientVaultBalance();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the allocations delegator.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param setAdapterLimitsRoleHolder Address of the initial SET_ADAPTER_LIMITS_ROLE holder.
     * @param swapAdaptersRoleHolder Address of the initial SWAP_ADAPTERS_ROLE holder.
     * @param allocateRoleHolder Address of the initial ALLOCATE_ROLE holder.
     * @param deallocateRoleHolder Address of the initial DEALLOCATE_ROLE holder.
     * @param adapters Initial adapters in allocation and withdrawal order.
     * @param absoluteLimits Initial absolute limits for each adapter.
     * @param shareLimits Initial share limits for each adapter, scaled by LIMIT_SHARE_SCALE.
     */
    struct InitParams {
        address defaultAdminRoleHolder;
        address setAdapterLimitsRoleHolder;
        address swapAdaptersRoleHolder;
        address allocateRoleHolder;
        address deallocateRoleHolder;
        address[] adapters;
        uint256[] absoluteLimits;
        uint256[] shareLimits;
    }

    /* EVENTS */

    /**
     * @notice Emitted when adapter limits are set.
     * @param adapter Adapter address.
     * @param absoluteLimit Absolute collateral limit.
     * @param shareLimit Share limit scaled by LIMIT_SHARE_SCALE.
     */
    event SetAdapterLimits(address indexed adapter, uint256 absoluteLimit, uint256 shareLimit);

    /**
     * @notice Emitted when an adapter is added to the ordered adapter list.
     * @param adapter Adapter address.
     * @param index Adapter index in the ordered list.
     */
    event AddAdapter(address indexed adapter, uint256 index);

    /**
     * @notice Emitted when two adapter positions are swapped.
     * @param index1 First adapter index.
     * @param index2 Second adapter index.
     * @param adapter1 Adapter moved into index2.
     * @param adapter2 Adapter moved into index1.
     */
    event SwapAdapters(uint256 indexed index1, uint256 indexed index2, address adapter1, address adapter2);

    /**
     * @notice Emitted when collateral is allocated to an adapter.
     * @param adapter Adapter address.
     * @param assets Amount allocated.
     */
    event Allocate(address indexed adapter, uint256 assets);

    /**
     * @notice Emitted when collateral is deallocated from an adapter.
     * @param adapter Adapter address.
     * @param assets Amount deallocated.
     */
    event Deallocate(address indexed adapter, uint256 assets);

    /**
     * @notice Emitted when an over-limit adapter is deallocated permissionlessly.
     * @param adapter Adapter address.
     * @param assets Amount deallocated.
     */
    event ForceDeallocate(address indexed adapter, uint256 assets);

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
     * @notice Get the number of configured adapters.
     * @return length Adapter count.
     */
    function adaptersLength() external view returns (uint256 length);

    /**
     * @notice Get an adapter at an ordered index.
     * @param index Adapter index.
     * @return adapter Adapter address.
     */
    function adapters(uint256 index) external view returns (address adapter);

    /**
     * @notice Get an adapter's one-based ordered index.
     * @param adapter Adapter address.
     * @return index One-based adapter index, or zero if not configured.
     */
    function adapterIndex(address adapter) external view returns (uint256 index);

    /**
     * @notice Get an adapter's tracked allocation.
     * @param adapter Adapter address.
     * @return assets Tracked allocated assets.
     */
    function adapterAllocated(address adapter) external view returns (uint256 assets);

    /**
     * @notice Get an adapter's absolute allocation limit.
     * @param adapter Adapter address.
     * @return limit Absolute collateral limit.
     */
    function absoluteLimitOf(address adapter) external view returns (uint256 limit);

    /**
     * @notice Get an adapter's relative share allocation limit.
     * @param adapter Adapter address.
     * @return limit Share limit scaled by LIMIT_SHARE_SCALE.
     */
    function shareLimitOf(address adapter) external view returns (uint256 limit);

    /**
     * @notice Get the active allocation limit for an adapter.
     * @param adapter Adapter address.
     * @return limit Effective allocation limit.
     */
    function allocationLimit(address adapter) external view returns (uint256 limit);

    /**
     * @notice Set adapter absolute and share limits, adding the adapter if needed.
     * @param adapter Adapter address.
     * @param absoluteLimit Absolute collateral limit.
     * @param shareLimit Share limit scaled by LIMIT_SHARE_SCALE.
     * @dev Only a SET_ADAPTER_LIMITS_ROLE holder can call this function.
     */
    function setAdapterLimits(address adapter, uint256 absoluteLimit, uint256 shareLimit) external;

    /**
     * @notice Swap two adapter positions in allocation and withdrawal order.
     * @param index1 First adapter index.
     * @param index2 Second adapter index.
     * @dev Only a SWAP_ADAPTERS_ROLE holder can call this function.
     */
    function swapAdapters(uint256 index1, uint256 index2) external;

    /**
     * @notice Allocate collateral to an adapter.
     * @param adapter Adapter address.
     * @param assets Amount of collateral to allocate.
     * @return allocated Amount allocated.
     * @dev Only an ALLOCATE_ROLE holder can call this function.
     */
    function allocate(address adapter, uint256 assets) external returns (uint256 allocated);

    /**
     * @notice Deallocate collateral from an adapter.
     * @param adapter Adapter address.
     * @param assets Amount of collateral to deallocate.
     * @return deallocated Amount deallocated.
     * @dev Only a DEALLOCATE_ROLE holder can call this function.
     */
    function deallocate(address adapter, uint256 assets) external returns (uint256 deallocated);

    /**
     * @notice Deallocate collateral from the calling adapter.
     * @param adapter Adapter address.
     * @param assets Amount of collateral to deallocate.
     * @return deallocated Amount deallocated.
     * @dev Only the adapter itself can call this function.
     */
    function deallocateAdapter(address adapter, uint256 assets) external returns (uint256 deallocated);

    /**
     * @notice Permissionlessly deallocate an adapter that exceeds its configured limit.
     * @param adapter Adapter address.
     * @param assets Maximum amount to deallocate.
     * @return deallocated Amount deallocated.
     */
    function forceDeallocate(address adapter, uint256 assets) external returns (uint256 deallocated);
}

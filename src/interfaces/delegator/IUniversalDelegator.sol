// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMulticallable} from "../common/IMulticallable.sol";

uint64 constant UNIVERSAL_DELEGATOR_TYPE = 4;

uint256 constant MAX_SHARE = 1e18;

uint256 constant MAX_ADAPTERS = 50;

// keccak256("ALLOCATE_ROLE")
bytes32 constant ALLOCATE_ROLE = 0x3e716b9e768f9140a805a7bd2ea8ed6273ee028841754af21433cf2650718e90;
// keccak256("DEALLOCATE_ROLE")
bytes32 constant DEALLOCATE_ROLE = 0x6fc880ed9b763496bee1eacc1616a9bd7192cd16545c429802620efc6999dcda;
// keccak256("ADD_ADAPTER_ROLE")
bytes32 constant ADD_ADAPTER_ROLE = 0xc29e756aabdeb9fb0e411860f152453e1129350b4366fdb14be986d3a939378b;
// keccak256("SWAP_ADAPTERS_ROLE")
bytes32 constant SWAP_ADAPTERS_ROLE = 0x1d53409af49f741b77991b0584075fbe3113d2af2e558244c183033fd9dd74ce;
// keccak256("REMOVE_ADAPTER_ROLE")
bytes32 constant REMOVE_ADAPTER_ROLE = 0xea290c8603ea61d0218a238127f9f470ebed6107d68e276ac9e0eef09c3a01ea;
// keccak256("SET_ADAPTER_LIMITS_ROLE")
bytes32 constant SET_ADAPTER_LIMITS_ROLE = 0x8c729dc4be31fd24714d9aa5498f0c485d31935b8850fc1f2d8fce2bfa1f0e35;
// keccak256("SET_AUTO_ALLOCATE_ADAPTERS_ROLE")
bytes32 constant SET_AUTO_ALLOCATE_ADAPTERS_ROLE = 0x8080881212c2315eb2f081d4587881789d9a59344d4a0f0b4f3daeb6877ed049;

/**
 * @title IUniversalDelegator
 * @notice Interface for the adapter-based universal delegator.
 */
interface IUniversalDelegator is IMulticallable {
    /* ERRORS */

    /**
     * @notice Raised when removing an adapter that still has assets.
     */
    error AdapterHasAssets();

    /**
     * @notice Raised when an adapter is already configured.
     */
    error AlreadyAdded();

    /**
     * @notice Raised when an adapter address is invalid.
     */
    error InvalidAdapter();

    /**
     * @notice Raised when adapter arrays have inconsistent lengths.
     */
    error InvalidLength();

    /**
     * @notice Raised when a protected role operation is invalid.
     */
    error InvalidRole();

    /**
     * @notice Raised when a share limit is above MAX_SHARE.
     */
    error InvalidShareLimit();

    /**
     * @notice Raised when a function can only be called by the contract itself.
     */
    error NotSelf();

    /**
     * @notice Raised when the caller is not the associated vault.
     */
    error NotVault();

    /**
     * @notice Raised when the connected vault version is older than required.
     */
    error OldVault();

    /**
     * @notice Internal sentinel used to return simulated deallocation through a revert.
     * @param assets Simulated deallocated assets.
     */
    error SimulatedDeallocate(uint256 assets);

    /**
     * @notice Raised when adding an adapter would exceed MAX_ADAPTERS.
     */
    error TooManyAdapters();

    /**
     * @notice Raised if the self-call simulation unexpectedly returns normally.
     */
    error UnexpectedSimulationSuccess();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the universal delegator.
     * @param allocateRoleHolder Address of the initial ALLOCATE_ROLE holder.
     * @param deallocateRoleHolder Address of the initial DEALLOCATE_ROLE holder.
     * @param addAdapterRoleHolder Address of the initial ADD_ADAPTER_ROLE holder.
     * @param swapAdaptersRoleHolder Address of the initial SWAP_ADAPTERS_ROLE holder.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param removeAdapterRoleHolder Address of the initial REMOVE_ADAPTER_ROLE holder.
     * @param setAdapterLimitsRoleHolder Address of the initial SET_ADAPTER_LIMITS_ROLE holder.
     * @param setAutoAllocateAdaptersRoleHolder Address of the initial SET_AUTO_ALLOCATE_ADAPTERS_ROLE holder.
     */
    struct InitParams {
        address allocateRoleHolder;
        address deallocateRoleHolder;
        address addAdapterRoleHolder;
        address swapAdaptersRoleHolder;
        address defaultAdminRoleHolder;
        address removeAdapterRoleHolder;
        address setAdapterLimitsRoleHolder;
        address setAutoAllocateAdaptersRoleHolder;
    }

    /* EVENTS */

    /**
     * @notice Emitted when an adapter is added.
     * @param adapter Adapter address.
     * @param index One-based adapter index.
     */
    event AddAdapter(address indexed adapter, uint256 index);

    /**
     * @notice Emitted when an adapter is removed.
     * @param adapter Adapter address.
     * @param index Former adapter index.
     */
    event RemoveAdapter(address indexed adapter, uint256 index);

    /**
     * @notice Emitted when adapter limits are set.
     * @param adapter Adapter address.
     * @param absoluteLimit Absolute asset limit.
     * @param shareLimit Share limit scaled by MAX_SHARE.
     */
    event SetLimits(address indexed adapter, uint256 absoluteLimit, uint256 shareLimit);

    /**
     * @notice Emitted when an adapter decreases its own limits.
     * @param assets Absolute asset limit decrease.
     * @param share Share limit decrease scaled by MAX_SHARE.
     */
    event DecreaseLimits(uint256 assets, uint256 share);

    /**
     * @notice Emitted when the ordered auto-allocation route is set.
     * @param adapters Adapter addresses.
     */
    event SetAutoAllocateAdapters(address[] adapters);

    /**
     * @notice Emitted when two adapters are swapped in the adapter route.
     * @param adapter1 First adapter address.
     * @param adapter2 Second adapter address.
     */
    event SwapAdapters(address indexed adapter1, address indexed adapter2);

    /**
     * @notice Emitted when assets are allocated to an adapter.
     * @param adapter Adapter address.
     * @param assets Allocated assets.
     * @param totalAssets Total assets in the adapter.
     */
    event Allocate(address indexed adapter, uint256 assets, uint256 totalAssets);

    /**
     * @notice Emitted when assets are deallocated from an adapter.
     * @param adapter Adapter address.
     * @param assets Deallocated assets.
     * @param totalAssets Total assets in the adapter.
     */
    event Deallocate(address indexed adapter, uint256 assets, uint256 totalAssets);

    /**
     * @notice Emitted when delayed deallocation is requested from an adapter.
     * @param adapter Adapter address.
     * @param assets Assets requested for delayed deallocation.
     */
    event RequestDeallocate(address indexed adapter, uint256 assets);

    /**
     * @notice Emitted after pending queue assets are swept.
     * @param pendingAssets Assets still pending after the sweep.
     */
    event SweepPending(uint256 pendingAssets);

    /**
     * @notice Emitted when the delegator is initialized.
     * @param params Initialization parameters.
     */
    event Initialize(InitParams params);

    /* FUNCTIONS */

    /**
     * @notice Get the associated vault address.
     * @return vaultAddress Address of the vault.
     */
    function vault() external view returns (address vaultAddress);

    /**
     * @notice Get the total number of unique adapter indexes assigned.
     * @return count Total assigned adapter indexes.
     */
    function totalAdapters() external view returns (uint16 count);

    /**
     * @notice Get an adapter at an ordered position.
     * @param index Zero-based adapter array index.
     * @return adapter Adapter address.
     */
    function adapters(uint256 index) external view returns (address adapter);

    /**
     * @notice Get a pending adapter index.
     * @param index Pending adapter array index.
     * @return pendingIndex Stable one-based adapter index.
     */
    function adaptersWithPending(uint256 index) external view returns (uint16 pendingIndex);

    /**
     * @notice Get an adapter in the auto-allocation route.
     * @param index Route array index.
     * @return adapter Adapter address.
     */
    function autoAllocateAdapters(uint256 index) external view returns (address adapter);

    /**
     * @notice Get the adapter assigned to a stable one-based index.
     * @param index Stable one-based adapter index.
     * @return adapter Adapter address.
     */
    function indexToAdapter(uint16 index) external view returns (address adapter);

    /**
     * @notice Get a stable one-based adapter index by address.
     * @param adapter Adapter address.
     * @return index Stable one-based adapter index.
     */
    function adapterToIndex(address adapter) external view returns (uint16 index);

    /**
     * @notice Get an adapter's relative share allocation limit.
     * @param adapter Adapter address.
     * @return limit Share limit scaled by MAX_SHARE.
     */
    function shareLimitOf(address adapter) external view returns (uint256 limit);

    /**
     * @notice Get an adapter's absolute allocation limit.
     * @param adapter Adapter address.
     * @return limit Absolute asset limit.
     */
    function absoluteLimitOf(address adapter) external view returns (uint256 limit);

    /**
     * @notice Get the delegator implementation version.
     * @return version Delegator version.
     */
    function VERSION() external view returns (uint64 version);

    /**
     * @notice Get total assets managed by all adapters.
     * @return assets Total adapter assets.
     */
    function totalAssets() external view returns (uint256 assets);

    /**
     * @notice Get an adapter's limit.
     * @param adapter Adapter address.
     * @return limit Limit.
     */
    function limitOf(address adapter) external view returns (uint256 limit);

    /**
     * @notice Get currently allocatable assets for an adapter after limits.
     * @param adapter Adapter address.
     * @return assets Allocatable assets.
     */
    function allocatable(address adapter) external view returns (uint256 assets);

    /**
     * @notice Simulate the assets that can be deallocated immediately through the configured route.
     * @dev Intentionally non-view because it uses a reverting self-call to roll back adapter state changes.
     * @return assets Simulated deallocated assets.
     */
    function deallocatable() external returns (uint256 assets);

    /**
     * @notice Add an adapter.
     * @param adapter Adapter address.
     * @return index Stable one-based adapter index.
     */
    function addAdapter(address adapter) external returns (uint16 index);

    /**
     * @notice Remove an adapter.
     * @param adapter Adapter address.
     * @dev Only updates the configured route and delegator accounting; callers must handle adapter assets and pending state before removal.
     */
    function removeAdapter(address adapter) external;

    /**
     * @notice Set adapter absolute and share limits.
     * @param adapter Adapter address.
     * @param assets Absolute asset limit.
     * @param share Share limit scaled by MAX_SHARE.
     */
    function setLimits(address adapter, uint256 assets, uint256 share) external;

    /**
     * @notice Swap two adapters in the ordered adapter route.
     * @param adapter1 First adapter address.
     * @param adapter2 Second adapter address.
     */
    function swapAdapters(address adapter1, address adapter2) external;

    /**
     * @notice Set the ordered auto-allocation route.
     * @param adapters Adapter addresses.
     */
    function setAutoAllocateAdapters(address[] calldata adapters) external;

    /**
     * @notice Allocate assets to an adapter.
     * @param adapter Adapter address.
     * @param assets Assets to allocate.
     * @return allocated Allocated assets.
     */
    function allocate(address adapter, uint256 assets) external returns (uint256 allocated);

    /**
     * @notice Allocate assets through the configured allocation route.
     * @param assets Assets to allocate.
     * @return allocated Allocated assets.
     */
    function allocateAll(uint256 assets) external returns (uint256 allocated);

    /**
     * @notice Allocate exact assets to an adapter, deallocating from the ordered route when vault free assets are insufficient.
     * @param adapter Adapter address.
     * @param assets Assets to allocate.
     * @return allocated Allocated assets.
     */
    function allocateExact(address adapter, uint256 assets) external returns (uint256 allocated);

    /**
     * @notice Deallocate assets from a specific adapter.
     * @param adapter Adapter address.
     * @param assets Assets to deallocate.
     * @return deallocated Deallocated assets.
     */
    function deallocate(address adapter, uint256 assets) external returns (uint256 deallocated);

    /**
     * @notice Deallocate assets through the configured deallocation route.
     * @param assets Assets to deallocate.
     * @return deallocated Deallocated assets.
     */
    function deallocateAll(uint256 assets) external returns (uint256 deallocated);

    /**
     * @notice Deallocate exact assets through the configured route.
     * @param assets Assets to deallocate.
     * @return deallocated Deallocated assets.
     */
    function deallocateExact(uint256 assets) external returns (uint256 deallocated);

    /**
     * @notice Force deallocation from a specific adapter and request any delayed remainder.
     * @param adapter Adapter address.
     * @param assets Assets to deallocate.
     * @return deallocated Assets deallocated now.
     * @return pending Assets requested for delayed deallocation.
     */
    function forceDeallocate(address adapter, uint256 assets) external returns (uint256 deallocated, uint256 pending);

    /**
     * @notice Decrease the caller adapter's absolute and share limits.
     * @param assets Absolute asset limit decrease.
     * @param share Share limit decrease scaled by MAX_SHARE.
     */
    function decreaseLimits(uint256 assets, uint256 share) external;

    /**
     * @notice Handle a vault deposit.
     * @dev Only the vault can call this function.
     */
    function onDeposit() external;

    /**
     * @notice Handle a withdrawal from the vault.
     * @dev Only the associated vault can call this function.
     * @param assets Assets to deallocate.
     */
    function onWithdraw(uint256 assets) external;

    /**
     * @notice Sweep pending queue assets through deallocation and filling.
     * @return pendingAssets Assets still pending after the sweep.
     */
    function sweepPending() external returns (uint256 pendingAssets);

}

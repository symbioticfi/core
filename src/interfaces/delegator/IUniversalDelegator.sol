// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint64 constant UNIVERSAL_DELEGATOR_TYPE = 4;

uint256 constant MAX_SHARE = 1e18;

uint256 constant MAX_ADAPTERS = 256;

// Keccak256("ADD_ADAPTER_ROLE").
bytes32 constant ADD_ADAPTER_ROLE = 0xc29e756aabdeb9fb0e411860f152453e1129350b4366fdb14be986d3a939378b;
// Keccak256("REMOVE_ADAPTER_ROLE").
bytes32 constant REMOVE_ADAPTER_ROLE = 0xea290c8603ea61d0218a238127f9f470ebed6107d68e276ac9e0eef09c3a01ea;
// Keccak256("SET_ADAPTER_LIMITS_ROLE").
bytes32 constant SET_ADAPTER_LIMITS_ROLE = 0x8c729dc4be31fd24714d9aa5498f0c485d31935b8850fc1f2d8fce2bfa1f0e35;
// Keccak256("SET_ADAPTERS_TO_ALLOCATE_ROLE").
bytes32 constant SET_ADAPTERS_TO_ALLOCATE_ROLE = 0x10b3e9cae2bb111c36d08a51e95396e14c52560455d4c3e9c0a753e7c33f7c68;
// Keccak256("SET_ADAPTERS_TO_DEALLOCATE_ROLE").
bytes32 constant SET_ADAPTERS_TO_DEALLOCATE_ROLE = 0xcefed1db406f4d2d0e0782d5fa455a94967e3492ec94c21aa426d775251a2c02;
// Keccak256("ALLOCATE_ROLE").
bytes32 constant ALLOCATE_ROLE = 0x3e716b9e768f9140a805a7bd2ea8ed6273ee028841754af21433cf2650718e90;
// Keccak256("DEALLOCATE_ROLE").
bytes32 constant DEALLOCATE_ROLE = 0x6fc880ed9b763496bee1eacc1616a9bd7192cd16545c429802620efc6999dcda;

/**
 * @title IUniversalDelegator
 * @notice Interface for the adapter-based universal delegator.
 */
interface IUniversalDelegator {
    /* ERRORS */

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
     * @notice Raised when the caller is not the associated vault.
     */
    error NotVault();

    /**
     * @notice Raised when the connected vault version is older than required.
     */
    error OldVault();

    /**
     * @notice Raised when adding an adapter would exceed MAX_ADAPTERS.
     */
    error TooManyAdapters();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the universal delegator.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param addAdapterRoleHolder Address of the initial ADD_ADAPTER_ROLE holder.
     * @param removeAdapterRoleHolder Address of the initial REMOVE_ADAPTER_ROLE holder.
     * @param setAdapterLimitsRoleHolder Address of the initial SET_ADAPTER_LIMITS_ROLE holder.
     * @param setAdaptersToAllocateRoleHolder Address of the initial SET_ADAPTERS_TO_ALLOCATE_ROLE holder.
     * @param setAdaptersToDeallocateRoleHolder Address of the initial SET_ADAPTERS_TO_DEALLOCATE_ROLE holder.
     * @param allocateRoleHolder Address of the initial ALLOCATE_ROLE holder.
     * @param deallocateRoleHolder Address of the initial DEALLOCATE_ROLE holder.
     * @param adapters Initial adapters.
     * @param absoluteLimits Initial absolute limits for each adapter.
     * @param shareLimits Initial share limits for each adapter, scaled by MAX_SHARE.
     */
    struct InitParams {
        address defaultAdminRoleHolder;
        address addAdapterRoleHolder;
        address removeAdapterRoleHolder;
        address setAdapterLimitsRoleHolder;
        address setAdaptersToAllocateRoleHolder;
        address setAdaptersToDeallocateRoleHolder;
        address allocateRoleHolder;
        address deallocateRoleHolder;
        address[] adapters;
        uint256[] absoluteLimits;
        uint256[] shareLimits;
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
     * @param index One-based adapter index.
     * @param absoluteLimit Absolute collateral limit.
     * @param shareLimit Share limit scaled by MAX_SHARE.
     */
    event SetLimits(uint8 indexed index, uint256 absoluteLimit, uint256 shareLimit);

    /**
     * @notice Emitted when the ordered allocation route is set.
     * @param indexes One-based adapter indexes.
     */
    event SetAdaptersToAllocate(uint8[] indexes);

    /**
     * @notice Emitted when the ordered deallocation route is set.
     * @param indexes One-based adapter indexes.
     */
    event SetAdaptersToDeallocate(uint8[] indexes);

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
     * @notice Get total assets managed by all adapters.
     * @return assets Total adapter assets.
     */
    function totalAssets() external view returns (uint256 assets);

    /**
     * @notice Get liquid assets held by the connected vault.
     * @return assets Free vault assets.
     */
    function freeAssets() external view returns (uint256 assets);

    /**
     * @notice Get an adapter's absolute allocation limit by one-based index.
     * @param index One-based adapter index.
     * @return limit Absolute collateral limit.
     */
    function absoluteLimitOf(uint8 index) external view returns (uint256 limit);

    /**
     * @notice Get an adapter's relative share allocation limit by one-based index.
     * @param index One-based adapter index.
     * @return limit Share limit scaled by MAX_SHARE.
     */
    function shareLimitOf(uint8 index) external view returns (uint256 limit);

    /**
     * @notice Get an adapter at an ordered position.
     * @param index Zero-based adapter array index.
     * @return adapter Adapter address.
     */
    function adapters(uint256 index) external view returns (address adapter);

    /**
     * @notice Get an adapter index in the allocation route.
     * @param index Route array index.
     * @return adapterIndex One-based adapter index.
     */
    function adaptersToAllocate(uint256 index) external view returns (uint8 adapterIndex);

    /**
     * @notice Get an adapter index in the deallocation route.
     * @param index Route array index.
     * @return adapterIndex One-based adapter index.
     */
    function adaptersToDeallocate(uint256 index) external view returns (uint8 adapterIndex);

    /**
     * @notice Get the pending-adapter bitmap.
     * @return bitmap Pending adapter bitmap keyed by one-based adapter index.
     */
    function adaptersWithPendingBitmap() external view returns (uint256 bitmap);

    /**
     * @notice Get currently allocatable assets for an adapter after limits.
     * @param adapter Adapter address.
     * @return assets Allocatable assets.
     */
    function allocatable(address adapter) external view returns (uint256 assets);

    /**
     * @notice Add an adapter.
     * @param adapter Adapter address.
     * @return index One-based adapter index.
     */
    function addAdapter(address adapter) external returns (uint8 index);

    /**
     * @notice Remove an adapter.
     * @param adapter Adapter address.
     */
    function removeAdapter(address adapter) external;

    /**
     * @notice Set adapter absolute and share limits.
     * @param adapter Adapter address.
     * @param assets Absolute collateral limit.
     * @param share Share limit scaled by MAX_SHARE.
     */
    function setLimits(address adapter, uint256 assets, uint256 share) external;

    /**
     * @notice Set the ordered deallocation route.
     * @param indexes One-based adapter indexes.
     */
    function setAdaptersToDeallocate(uint8[] calldata indexes) external;

    /**
     * @notice Set the ordered allocation route.
     * @param indexes One-based adapter indexes.
     */
    function setAdaptersToAllocate(uint8[] calldata indexes) external;

    /**
     * @notice Allocate collateral to an adapter.
     * @param adapter Adapter address.
     * @param assets Amount of collateral to allocate.
     * @return allocated Amount allocated.
     */
    function allocate(address adapter, uint256 assets) external returns (uint256 allocated);

    /**
     * @notice Allocate collateral through the configured allocation route.
     * @param assets Amount of collateral to allocate.
     * @return allocated Amount allocated.
     */
    function allocate(uint256 assets) external returns (uint256 allocated);

    /**
     * @notice Deallocate collateral through the configured deallocation route.
     * @param assets Amount of collateral to deallocate.
     * @return deallocated Amount deallocated.
     */
    function deallocate(uint256 assets) external returns (uint256 deallocated);

    /**
     * @notice Deallocate collateral from a specific adapter.
     * @param adapter Adapter address.
     * @param assets Amount of collateral to deallocate.
     * @return deallocated Amount deallocated.
     */
    function deallocate(address adapter, uint256 assets) external returns (uint256 deallocated);

    /**
     * @notice Deallocate an exact amount through the configured route.
     * @param assets Amount of collateral to deallocate.
     * @return deallocated Amount deallocated.
     */
    function deallocateExact(uint256 assets) external returns (uint256 deallocated);

    /**
     * @notice Force deallocation from a specific adapter and request any delayed remainder.
     * @param adapter Adapter address.
     * @param assets Amount of collateral to deallocate.
     * @return deallocated Amount deallocated now.
     * @return pending Amount requested for delayed deallocation.
     */
    function forceDeallocate(address adapter, uint256 assets) external returns (uint256 deallocated, uint256 pending);

    /**
     * @notice Handle a vault deposit.
     * @dev Only the vault can call this function.
     */
    function onDeposit() external;

    /**
     * @notice Handle a withdrawal queue request.
     * @dev Only the vault can call this function.
     */
    function onWithdrawRequest() external;

    /**
     * @notice Sweep pending queue assets through deallocation and filling.
     * @return pendingAssets Assets still pending after the sweep.
     */
    function sweepPending() external returns (uint256 pendingAssets);
}

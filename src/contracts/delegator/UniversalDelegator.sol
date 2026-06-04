// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Entity} from "../common/Entity.sol";
import {Multicallable} from "../common/Multicallable.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";
import {VaultV2} from "../vault/VaultV2.sol";
import {WithdrawalQueue} from "../vault/WithdrawalQueue.sol";

import {IAdapterRegistry} from "../../interfaces/IAdapterRegistry.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {
    IUniversalDelegator,
    MAX_ADAPTERS,
    MAX_SHARE,
    ALLOCATE_ROLE,
    DEALLOCATE_ROLE,
    ADD_ADAPTER_ROLE,
    SWAP_ADAPTERS_ROLE,
    REMOVE_ADAPTER_ROLE,
    SET_ADAPTER_LIMITS_ROLE,
    SET_AUTO_ALLOCATE_ADAPTERS_ROLE
} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {VAULT_V2_VERSION} from "../../interfaces/vault/IVaultV2.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @title UniversalDelegator
/// @notice Simple delegator that allocates vault assets across ordered adapters.
contract UniversalDelegator is
    Entity,
    StaticDelegateCallable,
    Multicallable,
    AccessControlUpgradeable,
    ReentrancyGuardTransient,
    IUniversalDelegator
{
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Address of the vault factory.
    address internal immutable VAULT_FACTORY;
    /// @dev Address of the adapter registry.
    address internal immutable ADAPTER_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IUniversalDelegator
    address public vault;
    /// @inheritdoc IUniversalDelegator
    uint16 public totalAdapters;
    /// @inheritdoc IUniversalDelegator
    address[] public adapters;
    /// @inheritdoc IUniversalDelegator
    uint16[] public adaptersWithPending;
    /// @inheritdoc IUniversalDelegator
    address[] public autoAllocateAdapters;
    /// @inheritdoc IUniversalDelegator
    mapping(uint16 index => address adapter) public indexToAdapter;
    /// @inheritdoc IUniversalDelegator
    mapping(address adapter => uint16 index) public adapterToIndex;

    /// @inheritdoc IUniversalDelegator
    mapping(address adapter => uint256 share) public shareLimitOf;
    /// @inheritdoc IUniversalDelegator
    mapping(address adapter => uint256 assets) public absoluteLimitOf;

    /// @dev Whether an adapter is currently configured.
    mapping(address adapter => bool status) internal _isAdapterAdded;

    /* CONSTRUCTOR */

    constructor(uint64 entityType, address vaultFactory, address adapterRegistry, address delegatorFactory)
        Entity(delegatorFactory, entityType)
    {
        VAULT_FACTORY = vaultFactory;
        ADAPTER_REGISTRY = adapterRegistry;
    }

    /// @inheritdoc IUniversalDelegator
    function VERSION() public pure returns (uint64) {
        return 2;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IUniversalDelegator
    function totalAssets() public view returns (uint256 assets) {
        for (uint256 i; i < adapters.length; ++i) {
            assets += IAdapter(adapters[i]).totalAssets();
        }
    }

    /// @inheritdoc IUniversalDelegator
    function limitOf(address adapter) public view returns (uint256) {
        return Math.min(absoluteLimitOf[adapter], VaultV2(vault).totalAssets().mulDiv(shareLimitOf[adapter], MAX_SHARE));
    }

    /// @inheritdoc IUniversalDelegator
    function allocatable(address adapter) public view returns (uint256) {
        // Calculate delegator limit.
        uint256 limit = limitOf(adapter);

        // Apply delegator limit.
        uint256 toAllocate = limit.saturatingSub(IAdapter(adapter).totalAssets());

        // Apply free assets.
        toAllocate = Math.min(toAllocate, VaultV2(vault).freeAssets());

        // Apply adapter limit.
        return Math.min(toAllocate, IAdapter(adapter).allocatable());
    }

    /// @inheritdoc IUniversalDelegator
    function deallocatable() public returns (uint256) {
        (, bytes memory returnDataInternal) = address(this)
            .call(abi.encodeCall(this.staticDelegateCall, (address(this), abi.encodeCall(this.__deallocateAll, ()))));
        (bool success, bytes memory returnData) = abi.decode(returnDataInternal, (bool, bytes));
        if (!success) {
            if (returnData.length == 0) revert();
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        }
        return abi.decode(returnData, (uint256));
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IUniversalDelegator
    function addAdapter(address adapter) public onlyRole(ADD_ADAPTER_ROLE) nonReentrant returns (uint16 index) {
        if (!IAdapterRegistry(ADAPTER_REGISTRY).isWhitelisted(vault, adapter)) {
            revert InvalidAdapter();
        }
        if (_isAdapterAdded[adapter]) {
            revert AlreadyAdded();
        }
        if (adapters.length == MAX_ADAPTERS) {
            revert TooManyAdapters();
        }
        index = adapterToIndex[adapter];
        if (index == 0) {
            index = ++totalAdapters;
            indexToAdapter[index] = adapter;
            adapterToIndex[adapter] = index;
        }
        adapters.push(adapter);
        _isAdapterAdded[adapter] = true;

        _grantRole(ALLOCATE_ROLE, adapter);
        _grantRole(DEALLOCATE_ROLE, adapter);

        emit AddAdapter(adapter, index);
    }

    /// @inheritdoc IUniversalDelegator
    function removeAdapter(address adapter) public onlyRole(REMOVE_ADAPTER_ROLE) nonReentrant {
        if (!_isAdapterAdded[adapter]) {
            revert InvalidAdapter();
        }
        if (IAdapter(adapter).totalAssets() > 0) {
            revert AdapterHasAssets();
        }
        _isAdapterAdded[adapter] = false;
        _removeOrdered(adapters, adapter);
        _removeOrdered(autoAllocateAdapters, adapter);

        uint16 index = adapterToIndex[adapter];
        for (uint256 i; i < adaptersWithPending.length; ++i) {
            if (adaptersWithPending[i] == index) {
                adaptersWithPending[i] = adaptersWithPending[adaptersWithPending.length - 1];
                adaptersWithPending.pop();
                break;
            }
        }

        _revokeRole(ALLOCATE_ROLE, adapter);
        _revokeRole(DEALLOCATE_ROLE, adapter);

        absoluteLimitOf[adapter] = 0;
        shareLimitOf[adapter] = 0;

        emit RemoveAdapter(adapter, index);
    }

    /// @inheritdoc IUniversalDelegator
    function setLimits(address adapter, uint256 assets, uint256 share)
        public
        onlyRole(SET_ADAPTER_LIMITS_ROLE)
        nonReentrant
    {
        _setLimits(adapter, assets, share);
    }

    /// @dev Set adapter limits and add the adapter to the ordered list on first use.
    function _setLimits(address adapter, uint256 assets, uint256 share) internal {
        if (!_isAdapterAdded[adapter]) {
            revert InvalidAdapter();
        }
        if (share > MAX_SHARE) {
            revert InvalidShareLimit();
        }

        absoluteLimitOf[adapter] = assets;
        shareLimitOf[adapter] = share;

        emit SetLimits(adapter, assets, share);
    }

    /// @inheritdoc IUniversalDelegator
    function swapAdapters(address adapter1, address adapter2) public onlyRole(SWAP_ADAPTERS_ROLE) nonReentrant {
        uint256 adapter1Pos = type(uint256).max;
        uint256 adapter2Pos = type(uint256).max;
        for (uint256 i; i < adapters.length; ++i) {
            if (adapters[i] == adapter1) {
                adapter1Pos = i;
            }
            if (adapters[i] == adapter2) {
                adapter2Pos = i;
            }
        }
        (adapters[adapter1Pos], adapters[adapter2Pos]) = (adapters[adapter2Pos], adapters[adapter1Pos]);
        emit SwapAdapters(adapter1, adapter2);
    }

    /// @inheritdoc IUniversalDelegator
    function setAutoAllocateAdapters(address[] calldata newAutoAllocateAdapters)
        public
        onlyRole(SET_AUTO_ALLOCATE_ADAPTERS_ROLE)
        nonReentrant
    {
        for (uint256 i; i < newAutoAllocateAdapters.length; ++i) {
            if (!_isAdapterAdded[newAutoAllocateAdapters[i]]) {
                revert InvalidAdapter();
            }
            for (uint256 j; j < i; ++j) {
                if (newAutoAllocateAdapters[j] == newAutoAllocateAdapters[i]) {
                    revert InvalidAdapter();
                }
            }
        }

        autoAllocateAdapters = newAutoAllocateAdapters;

        emit SetAutoAllocateAdapters(newAutoAllocateAdapters);
    }

    /// @inheritdoc IUniversalDelegator
    function allocate(address adapter, uint256 assets)
        public
        onlyRole(ALLOCATE_ROLE)
        nonReentrant
        returns (uint256 allocated)
    {
        if (sweepPending() > 0) {
            return 0;
        }
        return _allocate(adapter, assets);
    }

    /// @inheritdoc IUniversalDelegator
    function allocateAll(uint256 assets) public onlyRole(ALLOCATE_ROLE) nonReentrant returns (uint256 allocated) {
        if (sweepPending() > 0) {
            return 0;
        }
        return _allocateAll(assets);
    }

    /// @inheritdoc IUniversalDelegator
    function allocateExact(address adapter, uint256 assets)
        public
        onlyRole(ALLOCATE_ROLE)
        nonReentrant
        returns (uint256 allocated)
    {
        if (sweepPending() > 0) {
            return 0;
        }
        uint256 toDeallocate = assets.saturatingSub(VaultV2(vault).freeAssets());
        if (toDeallocate > _deallocateAll(toDeallocate)) {
            return 0;
        }
        return _allocate(adapter, assets);
    }

    /// @inheritdoc IUniversalDelegator
    function deallocate(address adapter, uint256 assets)
        public
        onlyRole(DEALLOCATE_ROLE)
        nonReentrant
        returns (uint256 deallocated)
    {
        deallocated = _deallocate(adapter, assets);
        sweepPending();
    }

    /// @inheritdoc IUniversalDelegator
    function deallocateAll(uint256 assets) public onlyRole(DEALLOCATE_ROLE) nonReentrant returns (uint256 deallocated) {
        deallocated = _deallocateAll(assets);
        sweepPending();
    }

    /// @inheritdoc IUniversalDelegator
    function deallocateExact(uint256 assets)
        public
        onlyRole(DEALLOCATE_ROLE)
        nonReentrant
        returns (uint256 deallocated)
    {
        if (sweepPending() > 0) {
            return 0;
        }
        return _deallocateAll(assets);
    }

    /// @inheritdoc IUniversalDelegator
    function forceDeallocate(address adapter, uint256 assets)
        public
        onlyRole(DEALLOCATE_ROLE)
        nonReentrant
        returns (uint256 deallocated, uint256 pending)
    {
        uint256 adapterTotalAssets = IAdapter(adapter).totalAssets();
        assets = Math.min(assets, adapterTotalAssets);

        // Try to deallocate full amount.
        deallocated = _deallocate(adapter, assets);

        // Request the remaining assets if deallocated is less than expected.
        if (deallocated < assets) {
            pending = assets - deallocated;
            _requestDeallocate(adapter, pending);
        }

        // Update the adapter's absolute limit to avoid new allocations.
        _setLimits(
            adapter,
            Math.min(absoluteLimitOf[adapter], adapterTotalAssets - deallocated - pending),
            shareLimitOf[adapter]
        );

        sweepPending();
    }

    /* PUBLIC FUNCTIONS (ADAPTER) */

    /// @inheritdoc IUniversalDelegator
    function decreaseLimits(uint256 assets, uint256 share) public nonReentrant {
        absoluteLimitOf[msg.sender] = absoluteLimitOf[msg.sender].saturatingSub(assets);
        shareLimitOf[msg.sender] = shareLimitOf[msg.sender].saturatingSub(share);

        emit DecreaseLimits(assets, share);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @dev Called after all pending tried to be filled.
    /// @inheritdoc IUniversalDelegator
    function onDeposit() public nonReentrant {
        if (vault != msg.sender) {
            revert NotVault();
        }

        // Skip allocation while pending assets remain.
        if (sweepPending() > 0) {
            return;
        }

        _allocateAll(type(uint256).max);
    }

    /// @inheritdoc IUniversalDelegator
    function onWithdraw(uint256 assets) public nonReentrant {
        if (vault != msg.sender) {
            revert NotVault();
        }

        _deallocateAll(assets);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IUniversalDelegator
    function sweepPending() public returns (uint256 pendingAssets) {
        address withdrawalQueue = VaultV2(vault).withdrawalQueue();

        // Try to sweep free assets as much as possible.
        for (uint256 i; i < adapters.length; ++i) {
            _deallocate(adapters[i], IAdapter(adapters[i]).freeAssets());
        }

        // Try to deallocate assets as much as possible to fill the queue.
        _deallocateAll(WithdrawalQueue(withdrawalQueue).pendingAssets().saturatingSub(VaultV2(vault).freeAssets()));
        WithdrawalQueue(withdrawalQueue).fill();

        // Fetch actual pending assets after filling the queue.
        pendingAssets = WithdrawalQueue(withdrawalQueue).pendingAssets();

        // Update requests or reset them.
        uint16[] memory previousAdaptersWithPending = adaptersWithPending;
        delete adaptersWithPending;

        // Request deallocation for remaining pending assets.
        uint256 remainingPendingAssets = pendingAssets;
        for (uint256 i; remainingPendingAssets > 0 && i < adapters.length; ++i) {
            address adapter = adapters[i];
            uint256 toRequest = Math.min(remainingPendingAssets, IAdapter(adapter).totalAssets());
            if (toRequest == 0) {
                continue;
            }
            _requestDeallocate(adapter, toRequest);
            adaptersWithPending.push(adapterToIndex[adapter]);
            remainingPendingAssets -= toRequest;
        }

        // Reset requests for adapters that are no longer pending.
        for (uint256 i; i < previousAdaptersWithPending.length; ++i) {
            bool found;
            for (uint256 j; j < adaptersWithPending.length; ++j) {
                if (previousAdaptersWithPending[i] == adaptersWithPending[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                _requestDeallocate(indexToAdapter[previousAdaptersWithPending[i]], 0);
            }
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

        vault = initVault;

        _grantRoleIfNotZero(ALLOCATE_ROLE, params.allocateRoleHolder);
        _grantRoleIfNotZero(DEALLOCATE_ROLE, params.deallocateRoleHolder);
        _grantRoleIfNotZero(ADD_ADAPTER_ROLE, params.addAdapterRoleHolder);
        _grantRoleIfNotZero(SWAP_ADAPTERS_ROLE, params.swapAdaptersRoleHolder);
        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(REMOVE_ADAPTER_ROLE, params.removeAdapterRoleHolder);
        _grantRoleIfNotZero(SET_ADAPTER_LIMITS_ROLE, params.setAdapterLimitsRoleHolder);
        _grantRoleIfNotZero(SET_AUTO_ALLOCATE_ADAPTERS_ROLE, params.setAutoAllocateAdaptersRoleHolder);

        emit Initialize(params);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Allocate assets through the configured auto-allocation route.
    function _allocateAll(uint256 assets) internal returns (uint256 allocated) {
        for (uint256 i; i < autoAllocateAdapters.length && assets > 0; ++i) {
            uint256 curAllocated = _allocate(autoAllocateAdapters[i], assets);
            allocated += curAllocated;
            assets -= curAllocated;
        }
    }

    /// @dev Deallocate assets through the ordered adapter route.
    function _deallocateAll(uint256 assets) internal returns (uint256 deallocated) {
        for (uint256 i; i < adapters.length && assets > 0; ++i) {
            uint256 curDeallocated = _deallocate(adapters[i], assets);
            deallocated += curDeallocated;
            assets = assets.saturatingSub(curDeallocated);
        }
    }

    /// @dev Allocate vault assets to an adapter.
    function _allocate(address adapter, uint256 assets) internal returns (uint256 allocated) {
        assets = Math.min(assets, allocatable(adapter));

        VaultV2(vault).pull(assets, adapter);
        allocated = IAdapter(adapter).allocate(assets);
        if (allocated < assets) {
            VaultV2(vault).push(assets - allocated, adapter);
        }

        emit Allocate(adapter, allocated, IAdapter(adapter).totalAssets());
    }

    /// @dev Deallocate adapter assets back into the vault.
    function _deallocate(address adapter, uint256 assets) internal returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(assets);
        if (deallocated > 0) {
            VaultV2(vault).push(deallocated, adapter);
        }

        emit Deallocate(adapter, deallocated, IAdapter(adapter).totalAssets());
    }

    /// @dev Forwards a delayed deallocation request to an adapter and emits the request event.
    function _requestDeallocate(address adapter, uint256 assets) internal {
        IAdapter(adapter).requestDeallocate(assets);

        emit RequestDeallocate(adapter, assets);
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }

    /// @dev Remove a value from an ordered address array.
    function _removeOrdered(address[] storage values, address value) internal {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == value) {
                for (uint256 j = i; j < values.length - 1; ++j) {
                    values[j] = values[j + 1];
                }
                values.pop();
                return;
            }
        }
    }

    /// @dev Prevent manual adapter role revocation while an adapter is configured.
    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        if ((role == ALLOCATE_ROLE || role == DEALLOCATE_ROLE) && _isAdapterAdded[account]) {
            revert InvalidRole();
        }
        return super._revokeRole(role, account);
    }

    /// @dev Internal self-call target used by deallocatable().
    function __deallocateAll() public returns (uint256) {
        if (address(this) != msg.sender) {
            revert NotSelf();
        }
        return _deallocateAll(type(uint256).max);
    }
}

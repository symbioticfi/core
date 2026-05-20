// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";
import {VaultV2} from "../vault/VaultV2.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {
    IAllocationsDelegator,
    LIMIT_SHARE_SCALE,
    SET_ADAPTER_LIMITS_ROLE,
    SWAP_ADAPTERS_ROLE,
    ALLOCATE_ROLE,
    DEALLOCATE_ROLE
} from "../../interfaces/delegator/IAllocationsDelegator.sol";
import {IDelegator} from "../../interfaces/delegator/IDelegator.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../interfaces/vault/IVaultV2.sol";
import {IWithdrawalQueue} from "../../interfaces/vault/IWithdrawalQueue.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AllocationsDelegator
/// @notice Simple delegator that allocates vault collateral across ordered adapters.
contract AllocationsDelegator is
    Entity,
    StaticDelegateCallable,
    AccessControlUpgradeable,
    ReentrancyGuard,
    IAllocationsDelegator
{
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Address of the vault factory.
    address internal immutable VAULT_FACTORY;
    /// @dev Address of the adapter registry.
    address internal immutable ADAPTER_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IDelegator
    address public vault;

    /// @inheritdoc IAllocationsDelegator
    address[] public adapters;

    /// @inheritdoc IAllocationsDelegator
    mapping(address adapter => uint256 index) public adapterIndex;

    /// @inheritdoc IAllocationsDelegator
    mapping(address adapter => uint256 assets) public adapterAllocated;

    /// @inheritdoc IAllocationsDelegator
    mapping(address adapter => uint256 limit) public absoluteLimitOf;

    /// @inheritdoc IAllocationsDelegator
    mapping(address adapter => uint256 limit) public shareLimitOf;

    /// @dev Total tracked allocation across all adapters.
    uint256 internal _allocated;

    /* MULTICALL */

    /// @inheritdoc IAllocationsDelegator
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

    constructor(uint64 entityType, address vaultFactory, address adapterRegistry, address delegatorFactory)
        Entity(delegatorFactory, entityType)
    {
        VAULT_FACTORY = vaultFactory;
        ADAPTER_REGISTRY = adapterRegistry;
    }

    /// @inheritdoc IAllocationsDelegator
    function VERSION() public pure returns (uint64) {
        return 1;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAllocationsDelegator
    function adaptersLength() public view returns (uint256) {
        return adapters.length;
    }

    /// @inheritdoc IDelegator
    function totalAssets() public view returns (uint256 assets) {
        address curVault = vault;
        if (curVault == address(0)) {
            return 0;
        }

        for (uint256 i; i < adapters.length; ++i) {
            assets += IAdapter(adapters[i]).totalAssets();
        }
    }

    /// @inheritdoc IAllocationsDelegator
    function allocationLimit(address adapter) public view returns (uint256) {
        address curVault = vault;
        if (curVault == address(0)) {
            return 0;
        }

        uint256 vaultAssets = VaultV2(vault).totalAssets();
        return Math.min(absoluteLimitOf[adapter], vaultAssets.mulDiv(shareLimitOf[adapter], LIMIT_SHARE_SCALE));
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IAllocationsDelegator
    function setAdapterLimits(address adapter, uint256 absoluteLimit, uint256 shareLimit)
        public
        onlyRole(SET_ADAPTER_LIMITS_ROLE)
    {
        _setAdapterLimits(adapter, absoluteLimit, shareLimit);
    }

    /// @inheritdoc IAllocationsDelegator
    function swapAdapters(uint256 index1, uint256 index2) public onlyRole(SWAP_ADAPTERS_ROLE) {
        if (index1 >= adapters.length || index2 >= adapters.length) {
            revert InvalidAdapter();
        }
        if (index1 == index2) {
            return;
        }

        address adapter1 = adapters[index1];
        address adapter2 = adapters[index2];

        adapters[index1] = adapter2;
        adapters[index2] = adapter1;
        adapterIndex[adapter1] = index2 + 1;
        adapterIndex[adapter2] = index1 + 1;

        emit SwapAdapters(index1, index2, adapter1, adapter2);
    }

    /* PUBLIC FUNCTIONS (ALLOCATOR) */

    /// @inheritdoc IAllocationsDelegator
    function allocate(address adapter, uint256 assets) public onlyRole(ALLOCATE_ROLE) nonReentrant returns (uint256) {
        return _allocate(adapter, assets);
    }

    /// @inheritdoc IAllocationsDelegator
    function deallocate(address adapter, uint256 assets)
        public
        onlyRole(DEALLOCATE_ROLE)
        nonReentrant
        returns (uint256)
    {
        _revertIfNotAdapter(adapter);
        return _deallocate(adapter, assets);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IAllocationsDelegator
    function forceDeallocate(address adapter, uint256 assets) public nonReentrant returns (uint256 deallocated) {
        _revertIfNotAdapter(adapter);

        uint256 excess = adapterAllocated[adapter].saturatingSub(allocationLimit(adapter));
        if (excess == 0) {
            revert AdapterNotOverLimit();
        }

        deallocated = _deallocate(adapter, Math.min(assets, excess));

        emit ForceDeallocate(adapter, deallocated);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IDelegator
    function sync() public nonReentrant {
        address curVault = vault;
        address queue = IVaultV2(curVault).withdrawalQueue();
        if (queue != msg.sender) {
            revert NotVault();
        }

        uint256 missing = IWithdrawalQueue(queue).pendingAssets().saturatingSub(_liquidAssets(curVault));
        for (uint256 i; i < adapters.length && missing != 0; ++i) {
            uint256 deallocated = _deallocate(adapters[i], missing);
            missing = missing.saturatingSub(deallocated);
        }
    }

    /// @inheritdoc IAllocationsDelegator
    function deallocateAdapter(address adapter, uint256 assets) public returns (uint256 deallocated) {
        _revertIfNotAdapter(adapter);
        if (msg.sender != adapter) {
            revert InvalidAdapter();
        }

        deallocated = _deallocate(adapter, assets);
    }

    /// @inheritdoc IDelegator
    function onDeposit(address caller, address receiver, uint256 assets, uint256 shares) public nonReentrant {
        if (vault != msg.sender) {
            revert NotVault();
        }

        if (assets != 0 && adapters.length != 0) {
            address adapter = adapters[0];
            uint256 allocatable = allocationLimit(adapter).saturatingSub(adapterAllocated[adapter]);
            if (allocatable != 0) {
                _allocate(adapter, Math.min(assets, allocatable));
            }
        }

        emit OnDeposit(caller, receiver, assets, shares);
    }

    /// @inheritdoc IDelegator
    function onRequestWithdraw(address caller, address receiver, uint256 assets, uint256 shares) public nonReentrant {
        if (IVaultV2(vault).withdrawalQueue() != msg.sender) {
            revert NotVault();
        }

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

        uint256 available = _liquidAssets(vault);
        if (available < assets) {
            uint256 missing = assets - available;
            for (uint256 i; i < adapters.length && missing != 0; ++i) {
                uint256 deallocated = _deallocate(adapters[i], missing);
                missing = missing.saturatingSub(deallocated);
            }
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

        if (
            params.adapters.length != params.absoluteLimits.length
                || params.adapters.length != params.shareLimits.length
        ) {
            revert InvalidLength();
        }

        vault = initVault;

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(SET_ADAPTER_LIMITS_ROLE, params.setAdapterLimitsRoleHolder);
        _grantRoleIfNotZero(SWAP_ADAPTERS_ROLE, params.swapAdaptersRoleHolder);
        _grantRoleIfNotZero(ALLOCATE_ROLE, params.allocateRoleHolder);
        _grantRoleIfNotZero(DEALLOCATE_ROLE, params.deallocateRoleHolder);

        for (uint256 i; i < params.adapters.length; ++i) {
            _setAdapterLimits(params.adapters[i], params.absoluteLimits[i], params.shareLimits[i]);
        }

        emit Initialize(params);
    }

    /* UTILITY FUNCTIONS */

    /// @dev Set adapter limits and add the adapter to the ordered list on first use.
    function _setAdapterLimits(address adapter, uint256 absoluteLimit, uint256 shareLimit) internal {
        if (adapter == address(0)) {
            revert InvalidAdapter();
        }
        if (shareLimit > LIMIT_SHARE_SCALE) {
            revert InvalidShareLimit();
        }

        if (adapterIndex[adapter] == 0) {
            if (!_isValidAdapter(adapter)) {
                revert InvalidAdapter();
            }

            adapters.push(adapter);
            adapterIndex[adapter] = adapters.length;

            emit AddAdapter(adapter, adapters.length - 1);
        }

        absoluteLimitOf[adapter] = absoluteLimit;
        shareLimitOf[adapter] = shareLimit;

        emit SetAdapterLimits(adapter, absoluteLimit, shareLimit);
    }

    /// @dev Allocate vault collateral to an adapter.
    function _allocate(address adapter, uint256 assets) internal returns (uint256 allocated) {
        _revertIfNotAdapter(adapter);
        allocated = Math.min(
            Math.min(
                Math.min(assets, allocationLimit(adapter).saturatingSub(adapterAllocated[adapter])),
                _liquidAssets(vault)
            ),
            IAdapter(adapter).allocatable()
        );

        if (allocated == 0) {
            return 0;
        }

        adapterAllocated[adapter] += allocated;
        _allocated += allocated;

        IVaultV2(vault).pull(allocated, adapter);
        IAdapter(adapter).allocate(allocated);

        emit Allocate(adapter, allocated);
    }

    /// @dev Deallocate adapter collateral back into the vault.
    function _deallocate(address adapter, uint256 assets) internal returns (uint256 deallocated) {
        assets = Math.min(assets, adapterAllocated[adapter]);
        if (assets == 0) {
            return 0;
        }

        deallocated = IAdapter(adapter).deallocate(assets);
        if (deallocated == 0) {
            return 0;
        }

        uint256 tracked = Math.min(deallocated, adapterAllocated[adapter]);
        adapterAllocated[adapter] -= tracked;
        _allocated -= tracked;

        IVaultV2(vault).push(deallocated, adapter);

        emit Deallocate(adapter, deallocated);
    }

    /// @dev Revert when an adapter is not configured.
    function _revertIfNotAdapter(address adapter) internal view {
        if (adapterIndex[adapter] == 0) {
            revert InvalidAdapter();
        }
    }

    /// @dev Returns whether an adapter belongs to a whitelisted adapter factory and to this vault.
    function _isValidAdapter(address adapter) internal view returns (bool) {
        try IAdapter(adapter).FACTORY() returns (address adapterFactory) {
            if (!IRegistry(ADAPTER_REGISTRY).isEntity(adapterFactory) || !IRegistry(adapterFactory).isEntity(adapter)) {
                return false;
            }
        } catch {
            return false;
        }

        try IAdapter(adapter).vault() returns (address adapterVault) {
            return adapterVault == vault;
        } catch {
            return false;
        }
    }

    /// @dev Returns liquid collateral currently held by the vault.
    function _liquidAssets(address curVault) internal view returns (uint256) {
        return IERC20(IVaultV2(curVault).collateral()).balanceOf(curVault);
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}

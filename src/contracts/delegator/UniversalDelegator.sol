// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";
import {VaultV2} from "../vault/VaultV2.sol";
import {WithdrawalQueue} from "../vault/WithdrawalQueue.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IAdapterRegistry} from "../../interfaces/IAdapterRegistry.sol";
import {
    IUniversalDelegator,
    MAX_ADAPTERS,
    MAX_SHARE,
    ADD_ADAPTER_ROLE,
    REMOVE_ADAPTER_ROLE,
    SET_ADAPTER_LIMITS_ROLE,
    SET_ADAPTERS_TO_ALLOCATE_ROLE,
    SET_ADAPTERS_TO_DEALLOCATE_ROLE,
    SWAP_ADAPTERS_ROLE,
    ALLOCATE_ROLE,
    DEALLOCATE_ROLE
} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {VAULT_V2_VERSION} from "../../interfaces/vault/IVaultV2.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title UniversalDelegator
/// @notice Simple delegator that allocates vault collateral across ordered adapters.
contract UniversalDelegator is
    Entity,
    StaticDelegateCallable,
    AccessControlUpgradeable,
    ReentrancyGuard,
    IUniversalDelegator
{
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* IMMUTABLES */

    /// @dev Address of the vault factory.
    address internal immutable VAULT_FACTORY;
    /// @dev Address of the adapter registry.
    address internal immutable ADAPTER_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IUniversalDelegator
    address public vault;

    /// @inheritdoc IUniversalDelegator
    mapping(uint8 => uint256 assets) public absoluteLimitOf;
    /// @inheritdoc IUniversalDelegator
    mapping(uint8 => uint256 share) public shareLimitOf;

    /// @inheritdoc IUniversalDelegator
    address[] public adapters;
    /// @inheritdoc IUniversalDelegator
    uint8[] public adaptersToAllocate;
    /// @inheritdoc IUniversalDelegator
    uint8[] public adaptersToDeallocate;
    /// @inheritdoc IUniversalDelegator
    uint256 public adaptersWithPendingBitmap;
    /// @dev One-based adapter indexes by adapter address.
    mapping(address adapter => uint8) adapterIndex;

    /* MULTICALL */

    /// @inheritdoc IUniversalDelegator
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
    function allocatable() public view returns (uint256) {
        return IERC20(VaultV2(vault).asset()).balanceOf(vault);
    }

    /// @inheritdoc IUniversalDelegator
    function allocatable(address adapter) public view returns (uint256) {
        uint8 index = adapterIndex[adapter];
        if (index == 0) {
            return 0;
        }

        uint256 limit =
            Math.min(absoluteLimitOf[index], VaultV2(vault).totalAssets().mulDiv(shareLimitOf[index], MAX_SHARE));
        return Math.min(Math.min(limit, IAdapter(adapter).allocatable()), allocatable());
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IUniversalDelegator
    function addAdapter(address adapter) public onlyRole(ADD_ADAPTER_ROLE) returns (uint8) {
        return _addAdapter(adapter);
    }

    function _addAdapter(address adapter) internal returns (uint8 index) {
        address adapterFactory = IEntity(adapter).FACTORY();
        if (
            !IRegistry(adapterFactory).isEntity(adapter)
                || IAdapterRegistry(ADAPTER_REGISTRY).isWhitelisted(address(this), adapterFactory)
        ) {
            revert InvalidAdapter();
        }
        if (adapterIndex[adapter] > 0) {
            revert AlreadyAdded();
        }
        if (adapters.length >= MAX_ADAPTERS) {
            revert TooManyAdapters();
        }
        adapters.push(adapter);
        index = uint8(adapters.length);
        adapterIndex[adapter] = index;

        grantRole(ALLOCATE_ROLE, adapter);
        _grantRole(DEALLOCATE_ROLE, adapter);

        emit AddAdapter(adapter, index);
    }

    /// @inheritdoc IUniversalDelegator
    function removeAdapter(address adapter) public onlyRole(REMOVE_ADAPTER_ROLE) {
        uint8 index = adapterIndex[adapter];
        if (index == 0) {
            revert InvalidAdapter();
        }
        adapters[index] = adapters[adapters.length - 1];
        adapterIndex[adapters[index]] = index;

        adapters.pop();
        for (uint256 i = index - 1; i < adaptersToAllocate.length - 1; ++i) {
            adaptersToAllocate[i] = adaptersToAllocate[i + 1];
        }
        adaptersToAllocate.pop();

        for (uint256 i = index - 1; i < adaptersToDeallocate.length - 1; ++i) {
            adaptersToDeallocate[i] = adaptersToDeallocate[i + 1];
        }
        adaptersToDeallocate.pop();

        adaptersWithPendingBitmap &= ~(1 << index);

        _revokeRole(ALLOCATE_ROLE, adapter);
        _revokeRole(DEALLOCATE_ROLE, adapter);

        emit RemoveAdapter(adapter, index);
    }

    /// @inheritdoc IUniversalDelegator
    function setLimits(address adapter, uint256 assets, uint256 share) public onlyRole(SET_ADAPTER_LIMITS_ROLE) {
        _setLimits(adapter, assets, share);
    }

    /// @dev Set adapter limits and add the adapter to the ordered list on first use.
    function _setLimits(address adapter, uint256 assets, uint256 share) internal {
        uint8 index = adapterIndex[adapter];
        if (index == 0) {
            revert InvalidAdapter();
        }
        if (share > MAX_SHARE) {
            revert InvalidShareLimit();
        }

        absoluteLimitOf[index] = assets;
        shareLimitOf[index] = share;

        emit SetLimits(index, assets, share);
    }

    function setAdaptersToDeallocate(uint8[] calldata indexes) public onlyRole(SET_ADAPTERS_TO_DEALLOCATE_ROLE) {
        delete adaptersToDeallocate;
        adaptersToDeallocate = indexes;

        emit SetAdaptersToDeallocate(indexes);
    }

    function setAdaptersToAllocate(uint8[] calldata indexes) public onlyRole(SET_ADAPTERS_TO_ALLOCATE_ROLE) {
        delete adaptersToAllocate;
        adaptersToAllocate = indexes;

        emit SetAdaptersToAllocate(indexes);
    }

    /// @inheritdoc IUniversalDelegator
    function allocate(address adapter, uint256 assets) public onlyRole(ALLOCATE_ROLE) nonReentrant returns (uint256) {
        return _allocate(adapter, assets);
    }

    /// @inheritdoc IUniversalDelegator
    function deallocate(uint256 assets) public onlyRole(DEALLOCATE_ROLE) nonReentrant returns (uint256 deallocated) {
        for (uint8 i; i < adaptersToDeallocate.length; ++i) {
            deallocated = _deallocate(adapters[adaptersToDeallocate[i]], assets);
        }
    }

    /// @inheritdoc IUniversalDelegator
    function deallocate(address adapter, uint256 assets)
        public
        onlyRole(DEALLOCATE_ROLE)
        nonReentrant
        returns (uint256 deallocated)
    {
        return _deallocate(adapter, assets);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    // /// @inheritdoc IUniversalDelegator
    // function forceDeallocate(address adapter, uint256 assets)
    //     public
    //     nonReentrant
    //     returns (uint256 deallocated, uint256 pending)
    // {
    //     _revertIfNotAdapter(adapter);

    //     uint256 excess = adapterAllocated[adapter].saturatingSub(allocationLimit(adapter));
    //     if (excess == 0) {
    //         revert AdapterNotOverLimit();
    //     }

    //     (deallocated, pending) = _deallocate(adapter, Math.min(assets, excess));

    //     emit ForceDeallocate(adapter, deallocated);
    // }

    /// @inheritdoc IUniversalDelegator
    function sync() public nonReentrant {
        uint256 queuePendingAssets =
            WithdrawalQueue(VaultV2(vault).withdrawalQueue()).pendingAssets().saturatingSub(allocatable());
        if (queuePendingAssets == 0) {
            return;
        }

        queuePendingAssets = deallocate(queuePendingAssets);

        uint256 newAdaptersWithPendingBitmap;
        for (uint256 i; queuePendingAssets > 0; ++i) {
            uint256 index = adaptersToDeallocate[i];
            uint256 toRequest = Math.min(queuePendingAssets, IAdapter(adapters[index]).totalAssets());
            IAdapter(adapters[index]).requestDeallocate(toRequest);
            newAdaptersWithPendingBitmap |= 1 << index;
            queuePendingAssets -= toRequest;
        }

        uint256 bitmapToClear = adaptersWithPendingBitmap | newAdaptersWithPendingBitmap ^ newAdaptersWithPendingBitmap;
        if (bitmapToClear > 0) {
            for (uint256 i; i < 256; ++i) {
                if (bitmapToClear & (1 << i) > 0) {
                    IAdapter(adapters[i]).requestDeallocate(0);
                }
            }
        }
        adaptersWithPendingBitmap = newAdaptersWithPendingBitmap;
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IUniversalDelegator
    function onDeposit(address caller, address receiver, uint256 assets, uint256 shares) public nonReentrant {
        if (vault != msg.sender) {
            revert NotVault();
        }
        for (uint256 i; assets > 0 && i < adaptersToAllocate.length; ++i) {
            address adapter = adapters[adaptersToAllocate[i]];
            uint256 toAllocate = Math.min(assets, allocatable(adapter));
            if (toAllocate > 0) {
                assets -= _allocate(adapter, toAllocate);
            }
        }

        emit OnDeposit(caller, receiver, assets, shares);
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
            _addAdapter(params.adapters[i]);
            _setLimits(params.adapters[i], params.absoluteLimits[i], params.shareLimits[i]);
        }

        emit Initialize(params);
    }

    /* INTERNAL FUNCTIONS */

    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        if ((role == ALLOCATE_ROLE || role == DEALLOCATE_ROLE) && adapterIndex[account] > 0) {
            revert InvalidRole();
        }
        return super._revokeRole(role, account);
    }

    /// @dev Allocate vault collateral to an adapter.
    function _allocate(address adapter, uint256 assets) internal returns (uint256 allocated) {
        if (adapterIndex[adapter] == 0) {
            revert InvalidAdapter();
        }
        uint256 toAllocate = Math.min(assets, allocatable(adapter));
        if (toAllocate == 0) {
            return 0;
        }

        VaultV2(vault).pull(toAllocate, adapter);
        allocated = IAdapter(adapter).allocate(toAllocate);
        if (toAllocate > allocated) {
            VaultV2(vault).push(toAllocate - allocated, adapter);
        }

        emit Allocate(adapter, allocated);
    }

    /// @dev Deallocate adapter collateral back into the vault.
    function _deallocate(address adapter, uint256 assets) internal returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(assets);
        if (deallocated > 0) {
            VaultV2(vault).push(deallocated, adapter);
        }

        emit Deallocate(adapter, deallocated);
    }

    /// @dev Grant a role when the holder address is not zero.
    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}

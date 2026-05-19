// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratableEntity} from "../common/MigratableEntity.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IAllocationsDelegator} from "../../interfaces/delegator/IAllocationsDelegator.sol";
import {ICuratorRegistry} from "../../interfaces/adapters/ICuratorRegistry.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Adapter
/// @notice Base contract for vault adapters with shared vault validation.
abstract contract Adapter is MigratableEntity, IAdapter {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Vault factory used to validate adapter initialization vaults.
    address internal immutable VAULT_FACTORY;
    /// @dev Curator registry used to authorize loss recovery.
    address internal immutable CURATOR_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IAdapter
    address public vault;

    /* TRANSIENT STATE VARIABLES */

    /// @dev Marks recovery-triggered deallocations so accounting skips the normal path.
    bool internal transient _isRecover;

    /* MODIFIERS */

    modifier onlyCurator() {
        if (ICuratorRegistry(CURATOR_REGISTRY).getCurator(vault) != msg.sender) {
            revert NotCurator();
        }
        _;
    }

    /* MULTICALL */

    /// @inheritdoc IAdapter
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

    constructor(address adapterFactory, address vaultFactory, address curatorRegistry)
        MigratableEntity(adapterFactory)
    {
        VAULT_FACTORY = vaultFactory;
        CURATOR_REGISTRY = curatorRegistry;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function allocatable() public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view virtual returns (uint256);

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IAdapter
    function skim() public returns (uint256 amount) {
        return _skim();
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IAdapter
    function recover(uint256 amount) public onlyCurator {
        if (amount == 0) {
            revert ZeroAmount();
        }

        IERC20(IVaultV2(vault).collateral()).safeTransferFrom(msg.sender, address(this), amount);
        _recover(amount);
        skim();

        emit Recover(amount);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IAdapter
    function allocate(uint256 amount) public {
        if (IVaultV2(vault).delegator() != msg.sender) {
            revert NotVault();
        }

        _allocate(amount);
    }

    /// @inheritdoc IAdapter
    function deallocate(uint256 amount) public returns (uint256) {
        if (IVaultV2(vault).delegator() != msg.sender) {
            revert NotVault();
        }

        if (_isRecover) {
            address collateral = IVaultV2(vault).collateral();
            if (IERC20(collateral).allowance(address(this), vault) < amount) {
                IERC20(collateral).forceApprove(vault, type(uint256).max);
            }
            return amount;
        }
        return _deallocate(amount);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the delegator-tracked allocation for this adapter and vault.
    function _adapterAllocated() internal view returns (uint256) {
        return IAllocationsDelegator(IVaultV2(vault).delegator()).adapterAllocated(address(this));
    }

    /// @dev Recovers collateral back to the vault via the delegator deallocation hook.
    function _recover(uint256 amount) internal {
        _isRecover = true;
        _deallocateAdapter(amount);
        _isRecover = false;
    }

    /// @dev Deallocates this adapter through the vault's allocations delegator.
    function _deallocateAdapter(uint256 amount) internal returns (uint256) {
        return IAllocationsDelegator(IVaultV2(vault).delegator()).deallocateAdapter(address(this), amount);
    }

    /// @dev Skims excess collateral yield from the adapter for a vault.
    function _skim() internal virtual returns (uint256);

    /// @dev Allocates collateral from the vault into the adapter position.
    function _allocate(uint256 amount) internal virtual;

    /// @dev Deallocates collateral from the vault's adapter position.
    function _deallocate(uint256 amount) internal virtual returns (uint256);

    /* INITIALIZATION */

    /// @dev Initializes the adapter vault and adapter-specific state.
    function _initialize(uint64, address, bytes memory data) internal override {
        (address initVault, bytes memory initData) = abi.decode(data, (address, bytes));
        if (!IRegistry(VAULT_FACTORY).isEntity(initVault)) {
            revert InvalidVault();
        }
        vault = initVault;
        __initialize(initData);
    }

    /// @dev Initializes adapter-specific state.
    function __initialize(bytes memory) internal virtual {}

    /// @dev Migrates adapter-specific state.
    function _migrate(uint64 oldVersion, uint64 newVersion, bytes calldata data) internal override {
        _migrateAdapter(oldVersion, newVersion, data);
    }

    /// @dev Migrates adapter-specific state.
    function _migrateAdapter(uint64, uint64, bytes calldata) internal virtual {}

    /* STORAGE GAP */

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] internal __gap;
}

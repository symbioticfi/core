// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratableEntity} from "../common/MigratableEntity.sol";
import {Multicallable} from "../common/Multicallable.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Adapter
/// @notice Base contract for vault adapters with shared vault validation.
abstract contract Adapter is MigratableEntity, Multicallable, IAdapter {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Vault factory used to validate adapter initialization vaults.
    address internal immutable VAULT_FACTORY;

    /* STATE VARIABLES */

    /// @inheritdoc IAdapter
    address public vault;

    /* MODIFIERS */

    modifier onlyDelegator() {
        if (IVaultV2(vault).delegator() != msg.sender) {
            revert NotVault();
        }
        _;
    }

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory) MigratableEntity(adapterFactory) {
        VAULT_FACTORY = vaultFactory;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function allocatable() public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view virtual returns (uint256);

    /// @inheritdoc IAdapter
    function freeAssets() public view virtual returns (uint256) {
        return IERC20(IERC4626(vault).asset()).balanceOf(address(this));
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IAdapter
    function allocate(uint256 amount) public onlyDelegator returns (uint256) {
        return amount > 0 ? _allocate(amount) : 0;
    }

    /// @inheritdoc IAdapter
    function deallocate(uint256 amount) public virtual onlyDelegator returns (uint256) {
        uint256 curFreeAssets = freeAssets();
        return curFreeAssets + (curFreeAssets < amount ? _deallocate(amount - curFreeAssets) : 0);
    }

    /// @inheritdoc IAdapter
    function requestDeallocate(uint256 amount) public onlyDelegator {
        return _requestDeallocate(amount);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Allocates asset from the vault into the adapter position.
    function _allocate(uint256 amount) internal virtual returns (uint256) {}

    /// @dev Deallocates asset from the vault's adapter position.
    function _deallocate(uint256 amount) internal virtual returns (uint256) {}

    /// @dev Synchronizes adapter pending deallocation accounting.
    function _requestDeallocate(uint256 amount) internal virtual {}

    /* INITIALIZATION */

    /// @dev Initializes the adapter vault and adapter-specific state.
    function _initialize(uint64, address, bytes memory data) internal override {
        (address initVault, bytes memory initData) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(initVault)) {
            revert InvalidVault();
        }

        vault = initVault;
        emit SetVault(initVault);

        IERC20(IERC4626(vault).asset()).forceApprove(initVault, type(uint256).max);

        __initialize(initVault, initData);
    }

    /// @dev Initializes adapter-specific state.
    function __initialize(address, bytes memory) internal virtual {}

    /* MIGRATION */

    /// @dev Migration is intentionally unsupported for this implementation.
    function _migrate(uint64, uint64, bytes calldata) internal pure override {
        revert();
    }

    /* STORAGE GAP */

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] internal __gap;
}

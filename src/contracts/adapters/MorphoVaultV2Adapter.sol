// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IMorphoLiquidityAdapter} from "../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoLiquidityAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IMorphoVaultV2Factory} from "../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2Factory.sol";
import {IMorphoVaultV2} from "../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MorphoVaultV2Adapter
/// @notice VaultV2 adapter for Morpho ERC4626 vaults.
contract MorphoVaultV2Adapter is Adapter, IMorphoVaultV2Adapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Morpho vault factory used for curator-side vault validation.
    address internal immutable MORPHO_VAULT_FACTORY;
    /// @dev Required Morpho adapter registry for configured vaults.
    address internal immutable MORPHO_ADAPTER_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IMorphoVaultV2Adapter
    address public morphoVault;

    /* CONSTRUCTOR */

    constructor(
        address vaultFactory,
        address adapterFactory,
        address morphoVaultFactory,
        address morphoAdapterRegistry
    ) Adapter(vaultFactory, adapterFactory) {
        MORPHO_VAULT_FACTORY = morphoVaultFactory;
        MORPHO_ADAPTER_REGISTRY = morphoAdapterRegistry;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return
            freeAssets()
                + IMorphoVaultV2(morphoVault).previewRedeem(IMorphoVaultV2(morphoVault).balanceOf(address(this)));
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @dev Uses a self-call so zero-share deposits revert and roll back the Morpho transfer.
    function deposit(uint256 amount) public {
        if (address(this) != msg.sender) {
            revert NotSelf();
        }
        if (IMorphoVaultV2(morphoVault).deposit(amount, address(this)) == 0) {
            revert InsufficientAmount();
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Deposits asset from the calling vault into the configured Morpho vault.
    function _allocate(uint256 amount) internal override returns (uint256) {
        try this.deposit(amount) {
            return amount;
        } catch {}
        return 0;
    }

    /// @dev Withdraws asset for the calling vault from the configured Morpho vault.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        address liquidityAdapter = IMorphoVaultV2(morphoVault).liquidityAdapter();
        amount = Math.min(
            amount,
            Math.min(
                IMorphoVaultV2(morphoVault).previewRedeem(IMorphoVaultV2(morphoVault).balanceOf(address(this))),
                IERC20(IERC4626(vault).asset()).balanceOf(morphoVault)
                    + (liquidityAdapter == address(0) ? 0 : IMorphoLiquidityAdapter(liquidityAdapter).realAssets())
            )
        );
        if (amount == 0) {
            return 0;
        }

        try IMorphoVaultV2(morphoVault).withdraw(amount, address(this), address(this)) returns (uint256) {
            return amount;
        } catch {}
        return 0;
    }

    /* INITIALIZATION */

    /// @dev Initializes and permanently binds the Morpho vault.
    function __initialize(address, bytes memory data) internal override {
        address curMorphoVault = abi.decode(data, (address));

        if (
            curMorphoVault == address(0) || !IMorphoVaultV2Factory(MORPHO_VAULT_FACTORY).isVaultV2(curMorphoVault)
                || !IMorphoVaultV2(curMorphoVault).abdicated(IMorphoVaultV2.setAdapterRegistry.selector)
                || IMorphoVaultV2(curMorphoVault).adapterRegistry() != MORPHO_ADAPTER_REGISTRY
                || IMorphoVaultV2(curMorphoVault).asset() != IERC4626(vault).asset()
        ) {
            revert InvalidMorphoVault();
        }

        morphoVault = curMorphoVault;

        IERC20(IERC4626(vault).asset()).forceApprove(curMorphoVault, type(uint256).max);

        emit Initialize(curMorphoVault);
    }
}

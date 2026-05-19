// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {DEALLOCATE_BUFFER, IMorphoVaultV2Adapter} from "../../interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IMorphoLiquidityAdapter} from "../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoLiquidityAdapter.sol";
import {IMorphoVaultV2Factory} from "../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2Factory.sol";
import {IMorphoVaultV2} from "../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";
import {IRewards} from "../../interfaces/vault/IRewards.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MorphoVaultV2Adapter
/// @notice VaultV2 adapter for Morpho ERC4626 vaults.
contract MorphoVaultV2Adapter is Adapter, IMorphoVaultV2Adapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Morpho vault factory used for curator-side vault validation.
    address internal immutable MORPHO_VAULT_FACTORY;
    /// @dev Required Morpho adapter registry for configured vaults.
    address internal immutable MORPHO_ADAPTER_REGISTRY;
    /// @dev Rewards contract that receives skimmed adapter yield.
    address internal immutable REWARDS;

    /* STATE VARIABLES */

    /// @inheritdoc IMorphoVaultV2Adapter
    address public morphoVault;

    /* TRANSIENT STATE VARIABLES */

    /// @dev Allows curator-driven withdrawals to bypass the normal underwater guard.
    bool internal transient _isForceDeallocate;

    /* CONSTRUCTOR */

    constructor(
        address adapterFactory,
        address morphoVaultFactory,
        address morphoAdapterRegistry,
        address curatorRegistry,
        address rewards,
        address vaultFactory
    ) Adapter(adapterFactory, vaultFactory, curatorRegistry) {
        MORPHO_VAULT_FACTORY = morphoVaultFactory;
        MORPHO_ADAPTER_REGISTRY = morphoAdapterRegistry;
        REWARDS = rewards;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function skimmable() public view returns (uint256) {
        return totalAssets().saturatingSub(_adapterAllocated());
    }

    /// @inheritdoc IAdapter
    function allocatable() public view override(Adapter, IAdapter) returns (uint256) {
        if (morphoVault == address(0)) {
            return 0;
        }
        return super.allocatable();
    }

    /// @inheritdoc IAdapter
    function deallocatable() public view returns (uint256) {
        address curMorphoVault = morphoVault;
        if (curMorphoVault == address(0)) {
            return 0;
        }
        uint256 assets = totalAssets();
        uint256 allocated = _adapterAllocated();
        if (!_isForceDeallocate && allocated.saturatingSub(assets) > DEALLOCATE_BUFFER) {
            return 0;
        }
        address collateral = IMorphoVaultV2(curMorphoVault).asset();
        address liquidityAdapter = IMorphoVaultV2(curMorphoVault).liquidityAdapter();
        return Math.min(
            Math.min(
                assets,
                IERC20(collateral).balanceOf(curMorphoVault)
                    + (liquidityAdapter == address(0) ? 0 : IMorphoLiquidityAdapter(liquidityAdapter).realAssets())
            ),
            allocated
        );
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        address curMorphoVault = morphoVault;
        if (curMorphoVault == address(0)) {
            return 0;
        }
        return IMorphoVaultV2(curMorphoVault).previewRedeem(IMorphoVaultV2(curMorphoVault).balanceOf(address(this)));
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IMorphoVaultV2Adapter
    function forceDeallocate(uint256 amount) public onlyCurator returns (uint256 deallocated) {
        if (amount == 0) {
            revert InsufficientAmount();
        }

        _isForceDeallocate = true;
        deallocated = _deallocateAdapter(amount);
        _isForceDeallocate = false;

        emit ForceDeallocate(amount, deallocated);
    }

    /// @inheritdoc IMorphoVaultV2Adapter
    function setMorphoVault(address newMorphoVault) public onlyCurator {
        if (
            newMorphoVault != address(0)
                && (!IMorphoVaultV2Factory(MORPHO_VAULT_FACTORY).isVaultV2(newMorphoVault)
                    || IMorphoVaultV2(newMorphoVault).adapterRegistry() != MORPHO_ADAPTER_REGISTRY
                    || !IMorphoVaultV2(newMorphoVault).abdicated(IMorphoVaultV2.setAdapterRegistry.selector)
                    || IMorphoVaultV2(newMorphoVault).asset() != IVaultV2(vault).collateral())
        ) {
            revert InvalidMorphoVault();
        }
        address curMorphoVault = morphoVault;
        if (curMorphoVault != address(0) && totalAssets() > 0) {
            revert ActivePosition();
        }
        morphoVault = newMorphoVault;

        emit SetMorphoVault(newMorphoVault);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Withdraws excess Morpho yield back to the adapter and forwards it to rewards.
    function _skim() internal override returns (uint256 amount) {
        amount = skimmable();
        if (amount == 0) {
            return 0;
        }
        address curMorphoVault = morphoVault;
        try IMorphoVaultV2(curMorphoVault).withdraw(amount, address(this), address(this)) returns (uint256) {}
        catch {
            return 0;
        }
        address collateral = IMorphoVaultV2(curMorphoVault).asset();
        if (IERC20(collateral).allowance(address(this), REWARDS) < amount) {
            IERC20(collateral).forceApprove(REWARDS, type(uint256).max);
        }
        IRewards(REWARDS).distributeDonationRewards(vault, amount);
    }

    /// @dev Deposits collateral from the calling vault into the configured Morpho vault.
    function _allocate(uint256 amount) internal override {
        _skim();
        if (skimmable() > 0) {
            revert SkimFailed();
        }

        if (amount == 0) {
            return;
        }

        address curMorphoVault = morphoVault;
        address collateral = IMorphoVaultV2(curMorphoVault).asset();

        if (IERC20(collateral).allowance(address(this), curMorphoVault) < amount) {
            IERC20(collateral).forceApprove(curMorphoVault, type(uint256).max);
        }
        try this.deposit(curMorphoVault, amount, address(this)) {
            return;
        } catch {}

        _recover(amount);
    }

    /// @dev Uses an external self-call so zero-share deposits revert and roll back the Morpho transfer.
    function deposit(address targetMorphoVault, uint256 amount, address onBehalfOf) external {
        if (address(this) != msg.sender) {
            revert NotSelf();
        }
        if (IMorphoVaultV2(targetMorphoVault).deposit(amount, onBehalfOf) == 0) {
            revert InsufficientAmount();
        }
    }

    /// @dev Withdraws collateral for the calling vault from the configured Morpho vault.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        _skim();

        if (amount == 0) {
            return 0;
        }

        amount = Math.min(deallocatable(), amount);
        if (amount == 0) {
            return 0;
        }

        address curMorphoVault = morphoVault;
        address collateral = IMorphoVaultV2(curMorphoVault).asset();
        try IMorphoVaultV2(curMorphoVault).withdraw(amount, address(this), address(this)) returns (uint256) {
            if (IERC20(collateral).allowance(address(this), vault) < amount) {
                IERC20(collateral).forceApprove(vault, type(uint256).max);
            }
        } catch {
            amount = 0;
        }

        return amount;
    }
}

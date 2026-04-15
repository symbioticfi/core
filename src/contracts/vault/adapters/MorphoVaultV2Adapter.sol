// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";
import {ERC4626Math} from "../common/ERC4626Math.sol";
import {IAdapter} from "../../../interfaces/vault/IAdapter.sol";
import {ICuratorRegistry} from "../../../interfaces/vault/adapters/ICuratorRegistry.sol";
import {
    IMorphoLiquidityAdapter
} from "../../../interfaces/vault/adapters/morpho_vaultv2_adapter/IMorphoLiquidityAdapter.sol";
import {
    IMorphoVaultV2Adapter
} from "../../../interfaces/vault/adapters/morpho_vaultv2_adapter/IMorphoVaultV2Adapter.sol";
import {
    IMorphoVaultV2Factory
} from "../../../interfaces/vault/adapters/morpho_vaultv2_adapter/IMorphoVaultV2Factory.sol";
import {IMorphoVaultV2} from "../../../interfaces/vault/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";
import {IRewards} from "../../../interfaces/vault/IRewards.sol";
import {IVaultV2} from "../../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

/// @title MorphoVaultV2Adapter
/// @notice VaultV2 adapter for Morpho ERC4626 vaults.
contract MorphoVaultV2Adapter is Initializable, Adapter, ERC4626Math, IMorphoVaultV2Adapter {
    using Math for uint256;
    using SafeERC20 for address;

    /* IMMUTABLES */

    /// @notice Morpho vault factory used for curator-side vault validation.
    address internal immutable MORPHO_VAULT_FACTORY;
    /// @notice Required Morpho adapter registry for configured vaults.
    address internal immutable MORPHO_ADAPTER_REGISTRY;
    /// @notice Rewards contract that receives skimmed adapter yield.
    address internal immutable REWARDS;

    /* STATE VARIABLES */

    /// @inheritdoc IMorphoVaultV2Adapter
    mapping(address vault => address morphoVault) public morphoVaults;
    /// @inheritdoc IMorphoVaultV2Adapter
    mapping(address morphoVault => uint256 shares) public totalVaultShares;
    /// @inheritdoc IMorphoVaultV2Adapter
    mapping(address morphoVault => mapping(address vault => uint256 shares)) public vaultShares;

    /* CONSTRUCTOR */

    /// @notice Creates the Morpho adapter.
    /// @param morphoVaultFactory The Morpho vault factory.
    /// @param morphoAdapterRegistry The required Morpho adapter registry.
    /// @param curatorRegistry The curator registry.
    /// @param rewards The rewards contract that receives skimmed yield.
    /// @param vaultFactory The vault registry address.
    constructor(
        address morphoVaultFactory,
        address morphoAdapterRegistry,
        address curatorRegistry,
        address rewards,
        address vaultFactory
    ) Adapter(vaultFactory, curatorRegistry) {
        MORPHO_VAULT_FACTORY = morphoVaultFactory;
        MORPHO_ADAPTER_REGISTRY = morphoAdapterRegistry;
        REWARDS = rewards;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function skimmable(address vault) public view returns (uint256) {
        if (IVaultV2(vault).totalStake() == 0) {
            return 0;
        }
        return _getVaultAssets(vault).saturatingSub(IVaultV2(vault).adapterAllocated(address(this)));
    }

    /// @inheritdoc IAdapter
    function allocatable(address vault) public view override(Adapter, IAdapter) returns (uint256) {
        if (morphoVaults[vault] == address(0)) {
            return 0;
        }
        return super.allocatable(vault);
    }

    /// @inheritdoc IAdapter
    function deallocatable(address vault) public view returns (uint256) {
        address morphoVault = morphoVaults[vault];
        if (morphoVault == address(0)) {
            return 0;
        }
        address collateral = IMorphoVaultV2(morphoVault).asset();
        address liquidityAdapter = IMorphoVaultV2(morphoVault).liquidityAdapter();
        return Math.min(
            Math.min(
                _getVaultAssets(vault),
                collateral.balanceOf(morphoVault)
                    + (liquidityAdapter == address(0) ? 0 : IMorphoLiquidityAdapter(liquidityAdapter).realAssets())
            ),
            IVaultV2(vault).adapterAllocated(address(this))
        );
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Withdraws excess Morpho yield back to the adapter and forwards it to rewards.
    function _skim(address vault) internal override returns (uint256 amount) {
        amount = skimmable(vault);
        if (amount > 0) {
            address morphoVault = morphoVaults[vault];
            uint256 burnedShares =
                _previewWithdraw(amount, totalVaultShares[morphoVault], _getAdapterAssets(morphoVault));
            try IMorphoVaultV2(morphoVault).withdraw(amount, address(this), address(this)) returns (uint256) {
                vaultShares[morphoVault][vault] -= burnedShares;
                totalVaultShares[morphoVault] -= burnedShares;
            } catch {
                return 0;
            }
            address collateral = IMorphoVaultV2(morphoVault).asset();
            if (IERC20(collateral).allowance(address(this), REWARDS) < amount) {
                IMorphoVaultV2(morphoVault).asset().safeApproveWithRetry(REWARDS, type(uint256).max);
            }
            IRewards(REWARDS).distributeDonationRewards(vault, amount);
        }
    }

    /// @dev Deposits collateral from the calling vault into the configured Morpho vault.
    function _allocate(uint256 amount) internal override {
        _skim(msg.sender);

        if (amount == 0) {
            return;
        }

        address morphoVault = morphoVaults[msg.sender];
        address collateral = IMorphoVaultV2(morphoVault).asset();
        _increaseGlobalAllocated(collateral, amount);
        if (IERC20(collateral).allowance(address(this), morphoVault) < amount) {
            collateral.safeApproveWithRetry(morphoVault, type(uint256).max);
        }

        uint256 mintedShares = _previewDeposit(amount, totalVaultShares[morphoVault], _getAdapterAssets(morphoVault));
        try IMorphoVaultV2(morphoVault).deposit(amount, address(this)) returns (uint256) {
            vaultShares[morphoVault][msg.sender] += mintedShares;
            totalVaultShares[morphoVault] += mintedShares;
        } catch {
            _recover(msg.sender, amount);
        }
    }

    /// @dev Withdraws collateral for the calling vault from the configured Morpho vault.
    function _deallocate(uint256 amount) internal override returns (uint256 deallocated) {
        _skim(msg.sender);

        if (amount == 0) {
            return 0;
        }

        deallocated = Math.min(deallocatable(msg.sender), amount);
        if (deallocated > 0) {
            address morphoVault = morphoVaults[msg.sender];
            address collateral = IMorphoVaultV2(morphoVault).asset();
            uint256 burnedShares = _previewWithdraw(deallocated, totalVaultShares[morphoVault], _getAdapterAssets(morphoVault));
            try IMorphoVaultV2(morphoVault).withdraw(deallocated, address(this), address(this)) returns (uint256) {
                vaultShares[morphoVault][msg.sender] -= burnedShares;
                totalVaultShares[morphoVault] -= burnedShares;
            } catch {
                deallocated = 0;
            }

            if (deallocated > 0) {
                _decreaseGlobalAllocated(collateral, deallocated);
                if (IERC20(collateral).allowance(address(this), msg.sender) < deallocated) {
                    collateral.safeApproveWithRetry(msg.sender, type(uint256).max);
                }
            }
        }
    }

    /// @dev Returns the adapter's total claim on a Morpho vault in collateral units.
    /// @param morphoVault The Morpho vault being queried.
    /// @return assets The adapter asset balance represented in collateral units.
    function _getAdapterAssets(address morphoVault) internal view returns (uint256) {
        return IMorphoVaultV2(morphoVault).previewRedeem(morphoVault.balanceOf(address(this)));
    }

    /// @dev Returns the vault's pro-rata claim on the configured Morpho vault.
    /// @param vault The vault being queried.
    /// @return assets The vault asset balance represented in collateral units.
    function _getVaultAssets(address vault) internal view returns (uint256) {
        address morphoVault = morphoVaults[vault];
        if (morphoVault == address(0)) {
            return 0;
        }
        return
            _previewRedeem(
                vaultShares[morphoVault][vault], _getAdapterAssets(morphoVault), totalVaultShares[morphoVault]
            );
    }

    /* CURATOR FUNCTIONS */

    /// @inheritdoc IMorphoVaultV2Adapter
    function setMorphoVault(address vault, address newMorphoVault) public onlyVault(vault) onlyCurator(vault) {
        if (
            newMorphoVault != address(0)
                && (!IMorphoVaultV2Factory(MORPHO_VAULT_FACTORY).isVaultV2(newMorphoVault)
                    || IMorphoVaultV2(newMorphoVault).adapterRegistry() != MORPHO_ADAPTER_REGISTRY
                    || !IMorphoVaultV2(newMorphoVault).abdicated(IMorphoVaultV2.setAdapterRegistry.selector)
                    || IMorphoVaultV2(newMorphoVault).asset() != IVaultV2(vault).collateral())
        ) {
            revert InvalidMorphoVault();
        }
        address curMorphoVault = morphoVaults[vault];
        if (curMorphoVault != address(0) && vaultShares[curMorphoVault][vault] > 0) {
            revert ActivePosition();
        }
        morphoVaults[vault] = newMorphoVault;

        emit SetMorphoVault(vault, newMorphoVault);
    }
}

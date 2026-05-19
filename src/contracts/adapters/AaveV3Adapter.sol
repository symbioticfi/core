// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {IAaveV3Adapter, REFERRAL_CODE} from "../../interfaces/adapters/IAaveV3Adapter.sol";
import {IAaveV3Pool} from "../../interfaces/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IRewards} from "../../interfaces/vault/IRewards.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AaveV3Adapter
/// @notice VaultV2 adapter for Aave V3 supply positions.
contract AaveV3Adapter is Adapter, IAaveV3Adapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Core Aave V3 pool.
    address internal immutable AAVE_POOL;
    /// @dev Rewards contract that redistributes adapter yield to the vault.
    address internal immutable REWARDS;

    /* CONSTRUCTOR */

    constructor(
        address adapterFactory,
        address aavePool,
        address curatorRegistry,
        address rewards,
        address vaultFactory
    ) Adapter(adapterFactory, vaultFactory, curatorRegistry) {
        AAVE_POOL = aavePool;
        REWARDS = rewards;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAaveV3Adapter
    function aToken() public view returns (address) {
        return IAaveV3Pool(AAVE_POOL).getReserveAToken(IVaultV2(vault).collateral());
    }

    /// @inheritdoc IAdapter
    function skimmable() public view returns (uint256) {
        return totalAssets().saturatingSub(_adapterAllocated());
    }

    /// @inheritdoc IAdapter
    function allocatable() public view override(Adapter, IAdapter) returns (uint256) {
        if (aToken() == address(0)) {
            return 0;
        }
        return super.allocatable();
    }

    /// @inheritdoc IAdapter
    function deallocatable() public view returns (uint256) {
        if (aToken() == address(0)) {
            return 0;
        }
        return Math.min(
            Math.min(totalAssets(), IAaveV3Pool(AAVE_POOL).getVirtualUnderlyingBalance(IVaultV2(vault).collateral())),
            _adapterAllocated()
        );
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        if (aToken() == address(0)) {
            return 0;
        }
        return IERC20(aToken()).balanceOf(address(this));
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Withdraws excess Aave yield back to the adapter and forwards it to rewards.
    function _skim() internal override returns (uint256 amount) {
        amount = skimmable();
        if (amount == 0) {
            return 0;
        }
        address collateral = IVaultV2(vault).collateral();
        try IAaveV3Pool(AAVE_POOL).withdraw(collateral, amount, address(this)) returns (uint256) {}
        catch {
            return 0;
        }

        if (IERC20(collateral).allowance(address(this), REWARDS) < amount) {
            IERC20(collateral).forceApprove(REWARDS, type(uint256).max);
        }
        IRewards(REWARDS).distributeDonationRewards(vault, amount);
    }

    /// @dev Supplies collateral from the calling vault into Aave.
    function _allocate(uint256 amount) internal override {
        _skim();
        if (skimmable() > 0) {
            revert SkimFailed();
        }

        if (amount == 0) {
            return;
        }

        address collateral = IVaultV2(vault).collateral();

        if (IERC20(collateral).allowance(address(this), AAVE_POOL) < amount) {
            IERC20(collateral).forceApprove(AAVE_POOL, type(uint256).max);
        }
        try IAaveV3Pool(AAVE_POOL).supply(collateral, amount, address(this), REFERRAL_CODE) {
            return;
        } catch {}

        _recover(amount);
    }

    /// @dev Withdraws collateral for the calling vault from Aave when liquidity is available.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        _skim();

        if (amount == 0) {
            return 0;
        }

        amount = Math.min(deallocatable(), amount);
        if (amount == 0) {
            return 0;
        }

        address collateral = IVaultV2(vault).collateral();
        try IAaveV3Pool(AAVE_POOL).withdraw(collateral, amount, address(this)) returns (uint256) {
            if (IERC20(collateral).allowance(address(this), vault) < amount) {
                IERC20(collateral).forceApprove(vault, type(uint256).max);
            }
        } catch {
            amount = 0;
        }

        return amount;
    }
}

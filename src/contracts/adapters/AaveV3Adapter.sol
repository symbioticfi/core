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

    /* CONSTRUCTOR */

    constructor(address aavePool, address vaultFactory, address adapterFactory, address curatorRegistry)
        Adapter(vaultFactory, adapterFactory, curatorRegistry)
    {
        AAVE_POOL = aavePool;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAaveV3Adapter
    function aToken() public view returns (address) {
        return IAaveV3Pool(AAVE_POOL).getReserveAToken(IVaultV2(vault).asset());
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
        return Math.min(totalAssets(), IAaveV3Pool(AAVE_POOL).getVirtualUnderlyingBalance(IVaultV2(vault).asset()));
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        if (aToken() == address(0)) {
            return 0;
        }
        return IERC20(aToken()).balanceOf(address(this));
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Supplies asset from the calling vault into Aave.
    function _allocate(uint256 amount) internal override returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        try IAaveV3Pool(AAVE_POOL).supply(IVaultV2(vault).asset(), amount, address(this), REFERRAL_CODE) {
            return amount;
        } catch {}
        return 0;
    }

    /// @dev Withdraws asset for the calling vault from Aave when liquidity is available.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        amount = Math.min(deallocatable(), amount);
        if (amount == 0) {
            return 0;
        }

        try IAaveV3Pool(AAVE_POOL).withdraw(IVaultV2(vault).asset(), amount, address(this)) returns (uint256) {
            return amount;
        } catch {}
        return 0;
    }

    /* INITIALIZATION */

    /// @dev Approves the Aave pool to pull the adapter asset.
    function __initialize(address asset, bytes memory) internal override {
        IERC20(asset).forceApprove(AAVE_POOL, type(uint256).max);
    }
}

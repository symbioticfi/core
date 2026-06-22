// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";
import {CoWSwapConverter} from "./common/CoWSwapConverter.sol";
import {MerklClaimer} from "./common/MerklClaimer.sol";

import {IAaveV3Adapter, REFERRAL_CODE} from "../../interfaces/adapters/IAaveV3Adapter.sol";
import {IAaveV3Pool} from "../../interfaces/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AaveV3Adapter
/// @notice VaultV2 adapter for Aave V3 supply positions.
contract AaveV3Adapter is Adapter, CoWSwapConverter, MerklClaimer, IAaveV3Adapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Core Aave V3 pool.
    address internal immutable AAVE_POOL;

    /* STATE VARIABLES */

    /// @inheritdoc IAaveV3Adapter
    address public aToken;

    /* CONSTRUCTOR */

    constructor(
        address aavePool,
        address vaultFactory,
        address adapterFactory,
        address merklDistributor,
        address cowSwapSettlement
    ) Adapter(vaultFactory, adapterFactory) CoWSwapConverter(cowSwapSettlement) MerklClaimer(merklDistributor) {
        AAVE_POOL = aavePool;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return freeAssets() + IERC20(aToken).balanceOf(address(this));
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc CoWSwapConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data) public virtual override {
        if (tokenIn == aToken || tokenIn == IERC4626(vault).asset()) {
            revert InvalidTokenIn();
        }
        if (tokenOut != IERC4626(vault).asset()) {
            revert InvalidTokenOut();
        }
        super.convert(tokenIn, amountIn, tokenOut, data);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Supplies asset from the calling vault into Aave.
    function _allocate(uint256 amount) internal override returns (uint256) {
        try IAaveV3Pool(AAVE_POOL).supply(IERC4626(vault).asset(), amount, address(this), REFERRAL_CODE) {
            return amount;
        } catch {}
        return 0;
    }

    /// @dev Withdraws asset for the calling vault from Aave when liquidity is available.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        amount = Math.min(
            amount,
            Math.min(
                IERC20(aToken).balanceOf(address(this)),
                IAaveV3Pool(AAVE_POOL).getVirtualUnderlyingBalance(IERC4626(vault).asset())
            )
        );
        if (amount == 0) {
            return 0;
        }

        try IAaveV3Pool(AAVE_POOL).withdraw(IERC4626(vault).asset(), amount, address(this)) returns (uint256) {
            return amount;
        } catch {}
        return 0;
    }

    /* INITIALIZATION */

    /// @dev Approves the Aave pool to pull the adapter asset.
    function __initialize(address, bytes memory data) internal override {
        InitParams memory params = abi.decode(data, (InitParams));

        __CoWSwapConverter_init(params.converters);

        aToken = IAaveV3Pool(AAVE_POOL).getReserveAToken(IERC4626(vault).asset());
        if (aToken == address(0)) {
            revert InvalidAToken();
        }
        IERC20(IERC4626(vault).asset()).forceApprove(AAVE_POOL, type(uint256).max);
    }
}

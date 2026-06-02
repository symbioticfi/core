// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MigratableEntity} from "../../../common/MigratableEntity.sol";

import {IAccount} from "../../../../interfaces/adapters/ll-adapter/IAccount.sol";
import {ILiquidLaneOracle} from "../../../../interfaces/adapters/ll-adapter/ILiquidLaneOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Account
/// @notice Base account for integrations that redeem held inventory into the vault asset or a closely related
///         settlement token.
abstract contract Account is MigratableEntity, IAccount {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @notice Token submitted through this account.
    address public immutable TOKEN_TO_REDEEM;
    /// @inheritdoc IAccount
    address public immutable ORACLE;
    /// @dev 1e18 * token-to-redeem decimals, cached at construction.
    uint256 internal immutable TO_ASSETS_DIVISOR;

    /* STATE VARIABLES */

    /// @notice Adapter allowed to sweep realized vault assets.
    address public adapter;
    /// @inheritdoc IAccount
    address public vault;

    uint256 internal _assetUnit;

    /* CONSTRUCTOR */

    constructor(address factory, address oracle, address tokenToRedeem) MigratableEntity(factory) {
        ORACLE = oracle;
        TOKEN_TO_REDEEM = tokenToRedeem;
        TO_ASSETS_DIVISOR = 1e18 * 10 ** IERC20Metadata(tokenToRedeem).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAccount
    function totalAssets() public view virtual returns (uint256 assets) {
        address asset = IERC4626(vault).asset();
        assets = IERC20(asset).balanceOf(address(this));

        uint256 price = ILiquidLaneOracle(ORACLE).getPrice();
        if (asset != TOKEN_TO_REDEEM) {
            assets += _toAssets(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), price);
        }

        assets += _additionalAssets(asset, price);
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IAccount
    function sync() public virtual nonReentrant {
        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amountToRedeem == 0) {
            return;
        }

        _requestRedeem(amountToRedeem, ILiquidLaneOracle(ORACLE).getPrice());
    }

    /* INTERNAL FUNCTIONS */

    function _toAssets(uint256 amount, uint256 price) internal view returns (uint256) {
        return amount.mulDiv(price * _assetUnit, TO_ASSETS_DIVISOR);
    }

    function _fromBase18Asset(uint256 amount) internal view returns (uint256) {
        return amount.mulDiv(_assetUnit, 1e18);
    }

    function _additionalAssets(address asset, uint256 price) internal view virtual returns (uint256 assets) {}

    function _requestRedeem(uint256 amountToRedeem, uint256 price) internal virtual;

    function _approveRedemptionSpenders() internal virtual {}

    /* INITIALIZATION */

    function _initialize(uint64, address, bytes memory data) internal override {
        (address initAdapter, address initVault,) = abi.decode(data, (address, address, address));

        adapter = initAdapter;
        vault = initVault;

        address asset = IERC4626(initVault).asset();
        _assetUnit = 10 ** IERC20Metadata(asset).decimals();
        IERC20(asset).forceApprove(initAdapter, type(uint256).max);

        _approveRedemptionSpenders();
    }
}

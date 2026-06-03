// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MigratableEntity} from "../../common/MigratableEntity.sol";

import {IAccount} from "../../../interfaces/adapters/ll-adapter/IAccount.sol";
import {IOracle} from "../../../interfaces/adapters/ll-adapter/IOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Account
/// @notice Base account for token-to-redeem integrations.
abstract contract Account is MigratableEntity, IAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @notice Token submitted through this account.
    address public immutable TOKEN_TO_REDEEM;
    /// @inheritdoc IAccount
    address public immutable ORACLE;
    /// @dev 1e18 * token-to-redeem decimals.
    uint256 internal immutable TO_ASSETS_DIVISOR;

    /* STATE VARIABLES */

    /// @notice Adapter allowed to sweep realized vault assets.
    address public adapter;
    /// @inheritdoc IAccount
    address public vault;

    /// @dev Vault asset unit.
    address internal _asset;
    /// @dev Vault asset unit.
    uint256 internal _unit;

    /* CONSTRUCTOR */

    /// @notice Creates the account implementation.
    constructor(address factory, address oracle, address tokenToRedeem) MigratableEntity(factory) {
        TO_ASSETS_DIVISOR = 1e18 * 10 ** IERC20Metadata(tokenToRedeem).decimals();
        TOKEN_TO_REDEEM = tokenToRedeem;
        ORACLE = oracle;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAccount
    function totalAssets() public view returns (uint256 assets) {
        assets = IERC20(_asset).balanceOf(address(this));

        assets += _tokenToRedeemToAssets(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)));

        assets += _totalAssets();
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IAccount
    function sync() public nonReentrant {
        _sync();
    }

    /* INTERNAL FUNCTIONS */

    function _redemptionTokenToAssets(address token, uint256 amount) internal view returns (uint256) {
        uint256 dUnit = _unit;
        uint256 bUnit = 10 ** IERC20Metadata(token).decimals();
        return bUnit == dUnit ? amount : amount.mulDiv(dUnit, bUnit);
    }

    function _tokenToRedeemToAssets(uint256 amount) internal view returns (uint256) {
        return _tokenToRedeemToAssets(amount, IOracle(ORACLE).getPrice());
    }

    function _tokenToRedeemToAssets(uint256 amount, uint256 rate) internal view returns (uint256) {
        return amount.mulDiv(rate * _unit, TO_ASSETS_DIVISOR);
    }

    function _totalAssets() internal view virtual returns (uint256);

    function _sync() internal virtual;

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64, address, bytes memory data) internal virtual override {
        InitParams memory params = abi.decode(data, (InitParams));

        vault = params.vault;
        adapter = params.adapter;

        _asset = IERC4626(params.vault).asset();
        _unit = 10 ** IERC20Metadata(_asset).decimals();
        IERC20(_asset).forceApprove(params.adapter, type(uint256).max);
    }
}

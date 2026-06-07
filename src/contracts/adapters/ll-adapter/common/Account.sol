// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratableEntity} from "../../../common/MigratableEntity.sol";
import {CoWSwapConverter} from "../../common/CoWSwapConverter.sol";

import {IConverter} from "../../../../interfaces/adapters/common/IConverter.sol";
import {IAccount} from "../../../../interfaces/adapters/ll-adapter/IAccount.sol";
import {IOracle} from "../../../../interfaces/adapters/ll-adapter/IOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Account
/// @notice Base account for token-to-redeem integrations.
abstract contract Account is MigratableEntity, CoWSwapConverter, IAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IAccount
    address public immutable TOKEN_TO_REDEEM;
    /// @inheritdoc IAccount
    address public immutable ORACLE;
    /// @dev 1e18 * token-to-redeem decimals.
    uint256 internal immutable TO_ASSETS_DIVISOR;

    /* STATE VARIABLES */

    /// @inheritdoc IAccount
    address public adapter;
    /// @inheritdoc IAccount
    address public vault;

    /// @dev Vault asset unit.
    address internal _asset;
    /// @dev Vault asset unit.
    uint256 internal _unit;

    /* CONSTRUCTOR */

    /// @notice Creates the account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) MigratableEntity(factory) CoWSwapConverter(cowSwapSettlement, cowSwapVaultRelayer) {
        TO_ASSETS_DIVISOR = 1e18 * 10 ** IERC20Metadata(tokenToRedeem).decimals();
        TOKEN_TO_REDEEM = tokenToRedeem;
        ORACLE = oracle;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAccount
    function totalAssets() public view returns (uint256 assets) {
        assets = IERC20(_asset).balanceOf(address(this));

        uint256 tokenToRedeemBalance = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (tokenToRedeemBalance > 0) {
            assets += _tokenToRedeemToAssets(tokenToRedeemBalance);
        }

        assets += _totalAssets();
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IAccount
    function sync() public nonReentrant {
        _sync();
    }

    /// @inheritdoc CoWSwapConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data)
        public
        override(CoWSwapConverter, IConverter)
    {
        sync();

        if (tokenIn == _asset || tokenIn == TOKEN_TO_REDEEM) {
            revert InvalidTokenIn();
        }
        if (tokenOut != _asset) {
            revert InvalidTokenOut();
        }
        super.convert(tokenIn, amountIn, tokenOut, data);
    }

    /* INTERNAL FUNCTIONS */

    function _redemptionTokenToAssets(address token, uint256 amount) internal view returns (uint256) {
        uint256 dUnit = _unit;
        uint256 bUnit = 10 ** IERC20Metadata(token).decimals();
        return bUnit == dUnit ? amount : amount.mulDiv(dUnit, bUnit);
    }

    function _tokenToRedeemToAssets(uint256 amount) internal view returns (uint256) {
        uint256 rate = IOracle(ORACLE).getPrice();
        if (rate == 0) {
            revert InvalidOracle();
        }
        return _tokenToRedeemToAssets(amount, rate);
    }

    function _tokenToRedeemToAssets(uint256 amount, uint256 rate) internal view returns (uint256) {
        return amount.mulDiv(rate * _unit, TO_ASSETS_DIVISOR);
    }

    function _totalAssets() internal view virtual returns (uint256 assets);

    function _sync() internal virtual;

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64, address initOwner, bytes memory data) internal virtual override {
        (vault, adapter) = abi.decode(data, (address, address));

        address[] memory converters = new address[](1);
        converters[0] = initOwner;
        __CoWSwapConverter_init(converters);

        _asset = IERC4626(vault).asset();
        _unit = 10 ** IERC20Metadata(_asset).decimals();
        IERC20(_asset).forceApprove(adapter, type(uint256).max);
    }
}

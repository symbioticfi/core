// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {IFigureOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IFigureOracle.sol";
import {IFigureYieldVault} from "../../../../interfaces/adapters/ll-adapter/figure/IFigureYieldVault.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FigureOracle
/// @notice Oracle returning the Figure/Hastra redemption price in `1e18` precision.
contract FigureOracle is Oracle, IFigureOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IFigureOracle
    address public immutable TOKEN_TO_REDEEM;

    /// @inheritdoc IFigureOracle
    address public immutable ASYNC_REDEEM_VAULT;

    /// @dev Token-to-redeem unit.
    uint256 internal immutable TOKEN_UNIT;
    /// @dev Redemption token unit.
    uint256 internal immutable REDEMPTION_TOKEN_UNIT;

    /* CONSTRUCTOR */

    /// @notice Creates the Figure/Hastra redemption-price oracle.
    constructor(uint256 minPrice, uint256 maxPrice, address tokenToRedeem) Oracle(minPrice, maxPrice) {
        TOKEN_TO_REDEEM = tokenToRedeem;
        ASYNC_REDEEM_VAULT = IERC4626(tokenToRedeem).asset();
        TOKEN_UNIT = 10 ** IERC20Metadata(tokenToRedeem).decimals();
        REDEMPTION_TOKEN_UNIT = 10 ** IERC20Metadata(IFigureYieldVault(ASYNC_REDEEM_VAULT).asset()).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        return IFigureYieldVault(ASYNC_REDEEM_VAULT)
            .convertToAssets(IERC4626(TOKEN_TO_REDEEM).convertToAssets(TOKEN_UNIT)).mulDiv(1e18, REDEMPTION_TOKEN_UNIT);
    }
}

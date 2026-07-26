// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {ISThreeJaneOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/ISThreeJaneOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title SThreeJaneOracle
/// @notice Oracle returning the Three Jane sUSD3 redemption price in `1e18` precision.
contract SThreeJaneOracle is Oracle, ISThreeJaneOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc ISThreeJaneOracle
    address public immutable TOKEN_TO_REDEEM;

    /// @inheritdoc ISThreeJaneOracle
    address public immutable USD3;

    /// @dev sUSD3 token unit.
    uint256 internal immutable TOKEN_UNIT;
    /// @dev USDC token unit.
    uint256 internal immutable USDC_UNIT;

    /* CONSTRUCTOR */

    /// @notice Creates the Three Jane sUSD3 redemption-price oracle.
    constructor(uint256 minPrice, uint256 maxPrice, address tokenToRedeem) Oracle(minPrice, maxPrice) {
        TOKEN_TO_REDEEM = tokenToRedeem;
        USD3 = IERC4626(tokenToRedeem).asset();
        TOKEN_UNIT = 10 ** IERC20Metadata(tokenToRedeem).decimals();
        USDC_UNIT = 10 ** IERC20Metadata(IERC4626(USD3).asset()).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        return
            IERC4626(USD3).convertToAssets(IERC4626(TOKEN_TO_REDEEM).convertToAssets(TOKEN_UNIT))
                .mulDiv(1e18, USDC_UNIT);
    }
}

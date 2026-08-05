// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {IOpenEdenExpress} from "../../../../interfaces/adapters/ll-adapter/openeden/IOpenEdenExpress.sol";
import {IOpenEdenOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IOpenEdenOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title OpenEdenOracle
/// @notice Oracle returning the OpenEden HYBOND net redemption price in `1e18` precision.
contract OpenEdenOracle is Oracle, IOpenEdenOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IOpenEdenOracle
    address public immutable TOKEN_TO_REDEEM;

    /// @inheritdoc IOpenEdenOracle
    address public immutable EXPRESS;

    /// @dev Token-to-redeem unit.
    uint256 internal immutable TOKEN_UNIT;
    /// @dev Redemption token unit.
    uint256 internal immutable REDEMPTION_TOKEN_UNIT;

    /* CONSTRUCTOR */

    /// @notice Creates the OpenEden HYBOND redemption-price oracle.
    constructor(uint256 minPrice, uint256 maxPrice, address tokenToRedeem, address express) Oracle(minPrice, maxPrice) {
        TOKEN_TO_REDEEM = tokenToRedeem;
        EXPRESS = express;
        TOKEN_UNIT = 10 ** IERC20Metadata(tokenToRedeem).decimals();
        REDEMPTION_TOKEN_UNIT = 10 ** IERC20Metadata(IOpenEdenExpress(express).redeemAsset()).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        (,, uint256 netRedemptionAssets) = IOpenEdenExpress(EXPRESS).previewRedeem(TOKEN_UNIT);
        return netRedemptionAssets.mulDiv(1e18, REDEMPTION_TOKEN_UNIT);
    }
}

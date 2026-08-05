// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {INoonOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/INoonOracle.sol";
import {INoonRateProvider} from "../../../../interfaces/adapters/ll-adapter/noon/INoonRateProvider.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title NoonOracle
/// @notice Oracle returning a Noon rate-provider quote in `1e18` precision.
contract NoonOracle is Oracle, INoonOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc INoonOracle
    address public immutable RATE_PROVIDER;
    /// @inheritdoc INoonOracle
    address public immutable TOKEN_TO_REDEEM;
    /// @inheritdoc INoonOracle
    address public immutable QUOTE_TOKEN;

    /// @dev Base-token unit.
    uint256 internal immutable _baseUnit;
    /// @dev Quote-token unit.
    uint256 internal immutable _quoteUnit;

    /* CONSTRUCTOR */

    /// @notice Creates the bounded Noon oracle.
    constructor(uint256 minPrice, uint256 maxPrice, address rateProvider, address tokenToRedeem)
        Oracle(minPrice, maxPrice)
    {
        RATE_PROVIDER = rateProvider;
        TOKEN_TO_REDEEM = tokenToRedeem;
        QUOTE_TOKEN = IERC4626(tokenToRedeem).asset();
        _baseUnit = 10 ** IERC20Metadata(tokenToRedeem).decimals();
        _quoteUnit = 10 ** IERC20Metadata(QUOTE_TOKEN).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        return
            INoonRateProvider(RATE_PROVIDER).getQuote(_baseUnit, TOKEN_TO_REDEEM, QUOTE_TOKEN).mulDiv(1e18, _quoteUnit);
    }
}

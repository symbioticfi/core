// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {IMakinaMachine} from "../../../../interfaces/adapters/ll-adapter/makina/IMakinaMachine.sol";
import {IMakinaOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IMakinaOracle.sol";
import {IMakinaSharePriceOracle} from "../../../../interfaces/adapters/ll-adapter/makina/IMakinaSharePriceOracle.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MakinaOracle
/// @notice Oracle returning a Makina Machine share price in `1e18` precision.
contract MakinaOracle is Oracle, IMakinaOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IMakinaOracle
    address public immutable SHARE_PRICE_ORACLE;
    /// @inheritdoc IMakinaOracle
    address public immutable MACHINE;
    /// @inheritdoc IMakinaOracle
    uint48 public immutable STALENESS_DURATION;

    /// @dev Source oracle unit.
    uint256 internal immutable _priceUnit;

    /* CONSTRUCTOR */

    /// @notice Creates the Makina share-price oracle adapter.
    constructor(uint256 minPrice, uint256 maxPrice, address sharePriceOracle, address machine, uint48 stalenessDuration)
        Oracle(minPrice, maxPrice)
    {
        SHARE_PRICE_ORACLE = sharePriceOracle;
        MACHINE = machine;
        STALENESS_DURATION = stalenessDuration;
        _priceUnit = 10 ** IMakinaSharePriceOracle(sharePriceOracle).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        uint256 updatedAt = IMakinaMachine(MACHINE).lastGlobalAccountingTime();
        if (updatedAt == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > STALENESS_DURATION) {
            return 0;
        }
        return IMakinaSharePriceOracle(SHARE_PRICE_ORACLE).getSharePrice().mulDiv(1e18, _priceUnit);
    }
}

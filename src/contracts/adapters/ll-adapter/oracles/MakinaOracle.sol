// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IOracle} from "../../../../interfaces/adapters/ll-adapter/IOracle.sol";
import {IMakinaSharePriceOracle} from "../../../../interfaces/adapters/ll-adapter/makina/IMakinaSharePriceOracle.sol";
import {IMakinaOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IMakinaOracle.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MakinaOracle
/// @notice Oracle returning a Makina Machine share price in `1e18` precision.
contract MakinaOracle is IMakinaOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IMakinaOracle
    address public immutable SHARE_PRICE_ORACLE;

    /// @dev Source oracle unit.
    uint256 internal immutable _priceUnit;

    /* CONSTRUCTOR */

    /// @notice Creates the Makina share-price oracle adapter.
    constructor(address sharePriceOracle) {
        SHARE_PRICE_ORACLE = sharePriceOracle;
        _priceUnit = 10 ** IMakinaSharePriceOracle(sharePriceOracle).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IOracle
    function getPrice() public view returns (uint256) {
        return IMakinaSharePriceOracle(SHARE_PRICE_ORACLE).getSharePrice().mulDiv(1e18, _priceUnit);
    }
}

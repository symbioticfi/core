// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IOracle} from "../../../../interfaces/adapters/ll-adapter/IOracle.sol";

/// @title Oracle
/// @notice Base oracle with immutable price bounds.
abstract contract Oracle is IOracle {
    /* IMMUTABLES */

    /// @notice Minimum valid price.
    uint256 public immutable MIN_PRICE;

    /// @notice Maximum valid price.
    uint256 public immutable MAX_PRICE;

    /* CONSTRUCTOR */

    /// @notice Creates the bounded oracle.
    constructor(uint256 minPrice, uint256 maxPrice) {
        if (minPrice == 0 || minPrice >= maxPrice) {
            revert InvalidPriceRange();
        }

        MIN_PRICE = minPrice;
        MAX_PRICE = maxPrice;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IOracle
    function getPrice() public view virtual returns (uint256 price) {
        price = _getPrice();
        if (price < MIN_PRICE || price > MAX_PRICE) {
            revert InvalidPrice();
        }
    }

    /// @dev Returns the raw source price before range validation.
    function _getPrice() internal view virtual returns (uint256);
}

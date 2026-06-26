// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IOracle
 * @notice Interface for liquidity lane token oracles.
 */
interface IOracle {
    /* ERRORS */

    /**
     * @notice Raised when the fetched price is outside the configured bounds.
     */
    error InvalidPrice();

    /**
     * @notice Raised when the configured price bounds are invalid.
     */
    error InvalidPriceRange();

    /* FUNCTIONS */

    /**
     * @notice Returns the token price.
     * @return price Token price in 1e18 precision against a shared quote.
     */
    function getPrice() external view returns (uint256 price);
}

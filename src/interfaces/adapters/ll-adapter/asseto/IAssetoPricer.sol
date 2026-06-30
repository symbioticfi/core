// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAssetoPricer
 * @notice Interface for Asseto NAV pricers.
 */
interface IAssetoPricer {
    /* FUNCTIONS */

    /**
     * @notice Returns price data by price id.
     * @param priceId The price id.
     * @return price The price in 1e18 precision.
     * @return timestamp The price update timestamp.
     */
    function prices(uint256 priceId) external view returns (uint256 price, uint256 timestamp);

    /**
     * @notice Returns the latest price id.
     * @return priceId The latest price id.
     */
    function latestPriceId() external view returns (uint256 priceId);

    /**
     * @notice Returns the latest price.
     * @return price The latest price in 1e18 precision.
     */
    function getLatestPrice() external view returns (uint256 price);
}

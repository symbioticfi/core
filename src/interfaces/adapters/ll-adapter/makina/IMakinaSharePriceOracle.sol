// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMakinaSharePriceOracle
 * @notice Interface for Makina Machine share-price oracles.
 */
interface IMakinaSharePriceOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the share-price decimals.
     * @return decimals The decimal precision.
     */
    function decimals() external view returns (uint8 decimals);

    /**
     * @notice Returns the Machine share price.
     * @return price The share price.
     */
    function getSharePrice() external view returns (uint256 price);
}

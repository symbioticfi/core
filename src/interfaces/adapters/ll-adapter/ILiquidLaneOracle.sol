// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILiquidLaneOracle
 * @notice Interface for liquidity lane token oracles.
 */
interface ILiquidLaneOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the token price.
     * @return price Token price in 1e18 precision against a shared quote.
     */
    function getPrice() external view returns (uint256 price);
}

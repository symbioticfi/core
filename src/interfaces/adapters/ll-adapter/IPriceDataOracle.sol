// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "./IOracle.sol";

/**
 * @title IPriceDataOracle
 * @notice Interface for liquidity lane token oracles exposing the price update timestamp.
 */
interface IPriceDataOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the token price and its last update timestamp.
     * @return price Token price in 1e18 precision against a shared quote.
     * @return updatedAt Timestamp of the last price update.
     */
    function getPriceData() external view returns (uint256 price, uint48 updatedAt);
}

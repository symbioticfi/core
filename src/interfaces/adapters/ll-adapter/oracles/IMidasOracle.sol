// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneOracle} from "../ILiquidLaneOracle.sol";

/**
 * @title IMidasDataFeed
 * @notice Interface for Midas data feeds.
 */
interface IMidasDataFeed {
    /* FUNCTIONS */

    /**
     * @notice Fetches answer from aggregator and converts it to the base18 precision.
     * @return answer The fetched aggregator answer.
     */
    function getDataInBase18() external view returns (uint256 answer);
}

/**
 * @title IMidasOracle
 * @notice Interface for Midas-backed liquidity lane token oracles.
 */
interface IMidasOracle is ILiquidLaneOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the Midas data feed.
     * @return dataFeed The data feed address.
     */
    function DATA_FEED() external view returns (address dataFeed);
}

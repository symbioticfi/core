// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneOracle} from "../ILiquidLaneOracle.sol";

/**
 * @title IChainlinkOracle
 * @notice Interface for Chainlink-backed liquidity lane token oracles.
 */
interface IChainlinkOracle is ILiquidLaneOracle {
    /* ERRORS */

    /**
     * @notice Raised when the first aggregator is not configured.
     */
    error InvalidAggregator();

    /* FUNCTIONS */

    /**
     * @notice Returns the first Chainlink aggregator in the price path.
     * @return aggregator The first aggregator address.
     */
    function AGGREGATOR_0() external view returns (address aggregator);

    /**
     * @notice Returns the optional second Chainlink aggregator in the price path.
     * @return aggregator The second aggregator address.
     */
    function AGGREGATOR_1() external view returns (address aggregator);

    /**
     * @notice Returns the maximum acceptable staleness for the first aggregator.
     * @return duration The first aggregator staleness duration.
     */
    function STALENESS_DURATION_0() external view returns (uint48 duration);

    /**
     * @notice Returns the maximum acceptable staleness for the second aggregator.
     * @return duration The second aggregator staleness duration.
     */
    function STALENESS_DURATION_1() external view returns (uint48 duration);
}

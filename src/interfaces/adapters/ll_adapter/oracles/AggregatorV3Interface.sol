// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// solhint-disable-next-line interface-starts-with-i
/**
 * @title AggregatorV3Interface
 * @notice Minimal Chainlink aggregator interface used by liquidity lane oracles.
 */
interface AggregatorV3Interface {
    /**
     * @notice Returns the decimals used by answers from the aggregator.
     * @return decimals_ The answer decimals.
     */
    function decimals() external view returns (uint8 decimals_);

    /**
     * @notice Returns data for a specific round.
     * @param roundId The round id to query.
     * @return roundId_ The round id.
     * @return answer The reported answer.
     * @return startedAt The round start timestamp.
     * @return updatedAt The round update timestamp.
     * @return answeredInRound The round in which the answer was computed.
     */
    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80 roundId_, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /**
     * @notice Returns the latest available round data.
     * @return roundId The round id.
     * @return answer The reported answer.
     * @return startedAt The round start timestamp.
     * @return updatedAt The round update timestamp.
     * @return answeredInRound The round in which the answer was computed.
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// solhint-disable-next-line interface-starts-with-i
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @title Scaler
 * @notice Library for scaling values between different decimals and inverting them.
 */
library Scaler {
    /**
     * @notice Scales a value given its decimals to the target decimals.
     * @param value The value to scale.
     * @param decimals The base decimals of the value.
     * @param targetDecimals The target decimals.
     * @return The scaled value.
     */
    function scale(uint256 value, uint8 decimals, uint8 targetDecimals) internal pure returns (uint256) {
        if (decimals < targetDecimals) {
            uint256 decimalsDiff;
            unchecked {
                decimalsDiff = targetDecimals - decimals;
            }
            return value * 10 ** decimalsDiff;
        }
        if (decimals > targetDecimals) {
            uint256 decimalsDiff;
            unchecked {
                decimalsDiff = decimals - targetDecimals;
            }
            return value / 10 ** decimalsDiff;
        }
        return value;
    }

    /**
     * @notice Inverts a value given its decimals.
     * @param value The value to invert.
     * @param decimals The base decimals of the value.
     * @return The inverted value.
     * @dev Reverts if the value is zero.
     */
    function invert(uint256 value, uint8 decimals) internal pure returns (uint256) {
        return 10 ** (uint256(decimals) << 1) / value;
    }
}

/**
 * @title ChainlinkPriceFeed
 * @notice Library for fetching prices from Chainlink in a historical manner.
 * @dev It supports arbitrary aggregators' decimals, an arbitrary number of aggregator hops, and a possibility to invert prices.
 *      It supports most of Chainlink's aggregators through the whole history except the oldest ones not supporting `getRoundData()`.
 */
library ChainlinkPriceFeed {
    using Scaler for uint256;
    using Math for uint256;

    /**
     * @notice Reverts when the length is zero.
     */
    error ZeroLength();

    /**
     * @notice Reverts when the lengths are not equal.
     */
    error NotEqualLength();

    /**
     * @notice The offset for the phase in the roundId.
     */
    uint256 internal constant PHASE_OFFSET = 64;

    /**
     * @notice The number of decimals to normalize the price to.
     */
    uint8 internal constant BASE_DECIMALS = 18;

    /**
     * @notice The data for a round.
     * @param roundId The roundId (a concatenation of the phase and the original id).
     * @param answer The price.
     * @param startedAt The startedAt (deprecated).
     * @param updatedAt The updatedAt (the timestamp when the round was updated).
     * @param answeredInRound The answeredInRound (deprecated).
     */
    struct RoundData {
        uint80 roundId;
        uint256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    /**
     * @notice Returns the price at a given timestamp using one or two hops.
     * @param aggregators The price aggregators.
     * @param timestamp The timestamp.
     * @param inverts If to invert the fetched prices.
     * @param stalenessDurations The staleness durations (if too much time passed since the last update).
     * @return The price.
     * @dev Returns zero if the data is stale or unavailable.
     *      The price is normalized to the 18 decimals.
     */
    function getPriceAt(
        address[2] memory aggregators,
        uint48 timestamp,
        bool[2] memory inverts,
        uint48[2] memory stalenessDurations
    ) public view returns (uint256) {
        (address[] memory dynamicAggregators, bool[] memory dynamicInverts, uint48[] memory dynamicStalenessDurations) =
            toDynamicArrays(aggregators, inverts, stalenessDurations);
        return getPriceAt(dynamicAggregators, timestamp, dynamicInverts, dynamicStalenessDurations);
    }

    /**
     * @notice Returns the price at a given timestamp using one or more hops.
     * @param aggregators The price aggregators.
     * @param timestamp The timestamp.
     * @param inverts If to invert the fetched prices.
     * @param stalenessDurations The staleness durations (if too much time passed since the last update).
     * @return The price.
     * @dev Returns zero if the data is stale or unavailable.
     *      The price is normalized to the 18 decimals.
     */
    function getPriceAt(
        address[] memory aggregators,
        uint48 timestamp,
        bool[] memory inverts,
        uint48[] memory stalenessDurations
    ) public view returns (uint256) {
        uint256 length = aggregators.length;
        if (length == 0) {
            revert ZeroLength();
        }
        if (length != inverts.length || length != stalenessDurations.length) {
            revert NotEqualLength();
        }
        uint256 price = 10 ** BASE_DECIMALS;
        for (uint256 i; i < length; ++i) {
            price = price.mulDiv(
                getPriceAt(aggregators[i], timestamp, inverts[i], stalenessDurations[i]), 10 ** BASE_DECIMALS
            );
        }
        return price;
    }

    /**
     * @notice Returns the price at a given timestamp.
     * @param aggregator The price aggregator.
     * @param timestamp The timestamp.
     * @param invert If to invert the fetched price.
     * @param stalenessDuration The staleness duration (if too much time passed since the last update).
     * @return The price.
     * @dev Returns zero if the data is stale or unavailable.
     *      The price is normalized to the 18 decimals.
     */
    function getPriceAt(address aggregator, uint48 timestamp, bool invert, uint48 stalenessDuration)
        public
        view
        returns (uint256)
    {
        (bool success, RoundData memory roundData) = getPriceDataAt(aggregator, timestamp, invert, stalenessDuration);
        return success ? roundData.answer : 0;
    }

    /**
     * @notice Returns the price data at a given timestamp.
     * @param aggregator The price aggregator.
     * @param timestamp The timestamp.
     * @param invert If to invert the fetched price.
     * @param stalenessDuration The staleness duration (if too much time passed since the last update).
     * @return success If the data is available and not stale.
     * @return roundData The round data.
     * @dev The answer is normalized to the 18 decimals.
     */
    function getPriceDataAt(address aggregator, uint48 timestamp, bool invert, uint48 stalenessDuration)
        public
        view
        returns (bool success, RoundData memory roundData)
    {
        (success, roundData) = getRoundDataAt(aggregator, timestamp);
        if (!success || isStale(timestamp, roundData, stalenessDuration)) {
            return (false, roundData);
        }
        roundData.answer = roundData.answer.scale(AggregatorV3Interface(aggregator).decimals(), BASE_DECIMALS);
        if (invert) {
            roundData.answer = roundData.answer.invert(BASE_DECIMALS);
        }
    }

    /**
     * @notice Returns the round data at a given timestamp.
     * @param aggregator The price aggregator.
     * @param timestamp The timestamp.
     * @return success If the data is available.
     * @return roundData The round data.
     */
    function getRoundDataAt(address aggregator, uint48 timestamp)
        public
        view
        returns (bool, RoundData memory roundData)
    {
        if (timestamp > block.timestamp) {
            return (false, roundData);
        }

        // determine the latest phaseId
        uint16 latestPhaseId;
        {
            (bool latestRoundDataSuccess, RoundData memory latestRoundData) = getLatestRoundData(aggregator);
            if (!latestRoundDataSuccess) {
                return (false, roundData);
            }
            (latestPhaseId,) = deserializeIds(latestRoundData.roundId);
        }

        // find a phaseId which contains a needed aggregatorRoundId given the timestamp
        uint16 phaseId = latestPhaseId;
        for (; phaseId > 0; --phaseId) {
            uint80 roundId = serializeIds(phaseId, 1);
            (bool phaseRoundDataSuccess, RoundData memory phaseRoundData) = getRoundData(aggregator, roundId);
            if (phaseRoundDataSuccess && phaseRoundData.updatedAt <= timestamp) {
                break;
            }
        }
        if (phaseId == 0) {
            return (false, roundData);
        }

        // find the upper bound for further binary search
        uint64 aggregatorRoundId = 1;
        while (true) {
            (bool roundDataSuccess,) = getRoundData(aggregator, serializeIds(phaseId, aggregatorRoundId));
            if (!roundDataSuccess || aggregatorRoundId == type(uint64).max) {
                break;
            }
            aggregatorRoundId <<= 1;
        }

        // find the biggest roundId which which is less than or equal to the timestamp
        uint80 resultRoundId;
        {
            uint80 lowRoundId = serializeIds(phaseId, 1);
            uint80 highRoundId = serializeIds(phaseId, aggregatorRoundId - 1);

            while (lowRoundId <= highRoundId) {
                uint80 midRoundId = lowRoundId + ((highRoundId - lowRoundId) >> 1);
                (bool midRoundDataSuccess, RoundData memory midRoundData) = getRoundData(aggregator, midRoundId);
                if (!midRoundDataSuccess || midRoundData.updatedAt > timestamp) {
                    highRoundId = midRoundId - 1;
                } else {
                    resultRoundId = midRoundId;
                    lowRoundId = midRoundId + 1;
                }
            }
        }
        return getRoundData(aggregator, resultRoundId);
    }

    /**
     * @notice Returns the round data at a given roundId.
     * @param aggregator The price aggregator.
     * @param roundId The roundId.
     * @return success If the data is available.
     * @return roundData The round data.
     */
    function getRoundData(address aggregator, uint80 roundId) public view returns (bool, RoundData memory roundData) {
        try AggregatorV3Interface(aggregator).getRoundData(roundId) returns (
            uint80, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
        ) {
            roundData = RoundData({
                roundId: roundId,
                answer: uint256(answer),
                startedAt: startedAt,
                updatedAt: updatedAt,
                answeredInRound: answeredInRound
            });
            return (roundData.updatedAt > 0, roundData);
        } catch {}
        return (false, roundData);
    }

    /**
     * @notice Returns the latest price using one or two hops.
     * @param aggregators The price aggregators.
     * @param inverts If to invert the fetched prices.
     * @param stalenessDurations The staleness durations (if too much time passed since the last update).
     * @return The price.
     * @dev Returns zero if the data is stale or unavailable.
     *      The price is normalized to the 18 decimals.
     */
    function getLatestPrice(address[2] memory aggregators, bool[2] memory inverts, uint48[2] memory stalenessDurations)
        public
        view
        returns (uint256)
    {
        (address[] memory dynamicAggregators, bool[] memory dynamicInverts, uint48[] memory dynamicStalenessDurations) =
            toDynamicArrays(aggregators, inverts, stalenessDurations);
        return getLatestPrice(dynamicAggregators, dynamicInverts, dynamicStalenessDurations);
    }

    /**
     * @notice Returns the latest price using one or more hops.
     * @param aggregators The price aggregators.
     * @param inverts If to invert the fetched prices.
     * @param stalenessDurations The staleness durations (if too much time passed since the last update).
     * @return The price.
     * @dev Returns zero if the data is stale or unavailable.
     *      The price is normalized to the 18 decimals.
     */
    function getLatestPrice(address[] memory aggregators, bool[] memory inverts, uint48[] memory stalenessDurations)
        public
        view
        returns (uint256)
    {
        uint256 length = aggregators.length;
        if (length == 0) {
            revert ZeroLength();
        }
        if (length != inverts.length || length != stalenessDurations.length) {
            revert NotEqualLength();
        }
        uint256 price = 10 ** BASE_DECIMALS;
        for (uint256 i; i < length; ++i) {
            price = price.mulDiv(getLatestPrice(aggregators[i], inverts[i], stalenessDurations[i]), 10 ** BASE_DECIMALS);
        }
        return price;
    }

    /**
     * @notice Returns the latest price.
     * @param aggregator The price aggregator.
     * @param invert If to invert the fetched price.
     * @param stalenessDuration The staleness duration (if too much time passed since the last update).
     * @return The price.
     * @dev Returns zero if the data is stale or unavailable.
     *      The price is normalized to the 18 decimals.
     */
    function getLatestPrice(address aggregator, bool invert, uint48 stalenessDuration) public view returns (uint256) {
        (bool success, RoundData memory roundData) = getLatestPriceData(aggregator, invert, stalenessDuration);
        return success ? roundData.answer : 0;
    }

    /**
     * @notice Returns the latest price data.
     * @param aggregator The price aggregator.
     * @param invert If to invert the fetched price.
     * @param stalenessDuration The staleness duration (if too much time passed since the last update).
     * @return success If the data is available and not stale.
     * @return roundData The round data.
     * @dev The answer is normalized to the 18 decimals.
     */
    function getLatestPriceData(address aggregator, bool invert, uint48 stalenessDuration)
        public
        view
        returns (bool success, RoundData memory roundData)
    {
        (success, roundData) = getLatestRoundData(aggregator);
        if (!success || isStale(uint48(block.timestamp), roundData, stalenessDuration)) {
            return (false, roundData);
        }
        roundData.answer = roundData.answer.scale(AggregatorV3Interface(aggregator).decimals(), BASE_DECIMALS);
        if (invert) {
            roundData.answer = roundData.answer.invert(BASE_DECIMALS);
        }
    }

    /**
     * @notice Returns the latest round data.
     * @param aggregator The price aggregator.
     * @return success If the data is available.
     * @return roundData The round data.
     */
    function getLatestRoundData(address aggregator) public view returns (bool, RoundData memory roundData) {
        try AggregatorV3Interface(aggregator).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
        ) {
            roundData = RoundData({
                roundId: roundId,
                answer: uint256(answer),
                startedAt: startedAt,
                updatedAt: updatedAt,
                answeredInRound: answeredInRound
            });
            return (roundData.updatedAt > 0, roundData);
        } catch {}
        return (false, roundData);
    }

    /**
     * @notice Returns if the round data is stale.
     * @param timestamp The timestamp.
     * @param roundData The round data.
     * @param stalenessDuration The staleness duration (if too much time passed since the last update).
     * @return If the round data is stale.
     */
    function isStale(uint48 timestamp, RoundData memory roundData, uint48 stalenessDuration)
        public
        pure
        returns (bool)
    {
        return roundData.answer == 0 || roundData.answer >= (1 << 255) || roundData.answeredInRound < roundData.roundId
            || roundData.updatedAt + stalenessDuration < timestamp;
    }

    function serializeIds(uint16 phase, uint64 originalId) public pure returns (uint80) {
        return uint80(uint256(phase) << PHASE_OFFSET | originalId);
    }

    function deserializeIds(uint80 roundId) public pure returns (uint16, uint64) {
        return (uint16(roundId >> PHASE_OFFSET), uint64(roundId));
    }

    function toDynamicArrays(address[2] memory aggregators, bool[2] memory inverts, uint48[2] memory stalenessDurations)
        public
        pure
        returns (
            address[] memory dynamicAggregators,
            bool[] memory dynamicInverts,
            uint48[] memory dynamicStalenessDurations
        )
    {
        dynamicAggregators = new address[](2);
        dynamicInverts = new bool[](2);
        dynamicStalenessDurations = new uint48[](2);
        uint256 length;
        for (uint256 i; i < 2; ++i) {
            if (aggregators[i] != address(0)) {
                dynamicAggregators[length] = aggregators[i];
                dynamicInverts[length] = inverts[i];
                dynamicStalenessDurations[length] = stalenessDurations[i];
                ++length;
            }
        }
        assembly ("memory-safe") {
            mstore(dynamicAggregators, length)
            mstore(dynamicInverts, length)
            mstore(dynamicStalenessDurations, length)
        }
    }
}

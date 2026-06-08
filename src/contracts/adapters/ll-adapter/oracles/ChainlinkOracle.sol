// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "../../../../interfaces/adapters/ll-adapter/oracles/AggregatorV3Interface.sol";
import {IChainlinkOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IChainlinkOracle.sol";
import {IOracle} from "../../../../interfaces/adapters/ll-adapter/IOracle.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ChainlinkOracle
/// @notice Constructor-configured Chainlink oracle returning a token price in `1e18` precision.
contract ChainlinkOracle is IChainlinkOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IChainlinkOracle
    address public immutable AGGREGATOR_0;
    /// @inheritdoc IChainlinkOracle
    address public immutable AGGREGATOR_1;
    /// @inheritdoc IChainlinkOracle
    uint48 public immutable STALENESS_DURATION_0;
    /// @inheritdoc IChainlinkOracle
    uint48 public immutable STALENESS_DURATION_1;

    /* CONSTRUCTOR */

    /// @notice Creates the Chainlink-backed oracle.
    constructor(address[2] memory aggregators, uint48[2] memory stalenessDurations) {
        if (aggregators[0] == address(0)) {
            revert InvalidAggregator();
        }

        AGGREGATOR_0 = aggregators[0];
        AGGREGATOR_1 = aggregators[1];
        STALENESS_DURATION_0 = stalenessDurations[0];
        STALENESS_DURATION_1 = stalenessDurations[1];
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IOracle
    function getPrice() public view returns (uint256 price) {
        price = _getPrice(AGGREGATOR_0, STALENESS_DURATION_0);
        if (price == 0 || AGGREGATOR_1 == address(0)) {
            return price;
        }
        return price.mulDiv(_getPrice(AGGREGATOR_1, STALENESS_DURATION_1), 1e18);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the latest Chainlink answer normalized to 18 decimals, or zero if unavailable/stale.
    function _getPrice(address aggregator, uint48 stalenessDuration) internal view returns (uint256) {
        try AggregatorV3Interface(aggregator).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            if (
                answer <= 0 || answeredInRound < roundId || updatedAt == 0
                    || updatedAt + stalenessDuration < block.timestamp
            ) {
                return 0;
            }
            return uint256(answer).mulDiv(1e18, 10 ** AggregatorV3Interface(aggregator).decimals());
        } catch {
            return 0;
        }
    }
}

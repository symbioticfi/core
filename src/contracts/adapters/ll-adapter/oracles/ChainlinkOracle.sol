// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AggregatorV3Interface, ChainlinkPriceFeed} from "./libraries/ChainlinkPriceFeed.sol";

import {IChainlinkOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IChainlinkOracle.sol";
import {IOracle} from "../../../../interfaces/adapters/ll-adapter/IOracle.sol";
import {IPriceDataOracle} from "../../../../interfaces/adapters/ll-adapter/IPriceDataOracle.sol";

/// @title ChainlinkOracle
/// @notice Constructor-configured Chainlink oracle returning a token price in `1e18` precision.
contract ChainlinkOracle is IChainlinkOracle {
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
    function getPrice() public view returns (uint256) {
        return ChainlinkPriceFeed.getLatestPrice(
            [AGGREGATOR_0, AGGREGATOR_1], [false, false], [STALENESS_DURATION_0, STALENESS_DURATION_1]
        );
    }

    /// @inheritdoc IPriceDataOracle
    /// @dev The update timestamp is the older of the two aggregators' timestamps.
    function getPriceData() public view returns (uint256 price, uint48 updatedAt) {
        price = getPrice();
        (,,, uint256 timestamp,) = AggregatorV3Interface(AGGREGATOR_0).latestRoundData();
        updatedAt = uint48(timestamp);
        if (AGGREGATOR_1 != address(0)) {
            (,,, uint256 timestamp1,) = AggregatorV3Interface(AGGREGATOR_1).latestRoundData();
            if (timestamp1 < updatedAt) {
                updatedAt = uint48(timestamp1);
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";

contract MockAggregatorV3 {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setRound(int256 answer_, uint256 updatedAt_) external {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract MockMidasDataFeed {
    address public aggregator;
    uint256 internal _answer;

    constructor(address aggregator_) {
        aggregator = aggregator_;
    }

    function setAnswer(uint256 answer_) external {
        _answer = answer_;
    }

    function getDataInBase18() external view returns (uint256) {
        return _answer;
    }
}

contract PriceDataOraclesTest is Test {
    function testMidasOracleReturnsPriceAndAggregatorUpdatedAt() public {
        MockAggregatorV3 aggregator = new MockAggregatorV3(8);
        MockMidasDataFeed dataFeed = new MockMidasDataFeed(address(aggregator));
        dataFeed.setAnswer(0.93e18);
        aggregator.setRound(0.93e8, 1_750_000_000);

        MidasOracle oracle = new MidasOracle(address(dataFeed));
        (uint256 price, uint48 updatedAt) = oracle.getPriceData();
        assertEq(price, 0.93e18);
        assertEq(updatedAt, 1_750_000_000);
    }

    function testChainlinkOracleReturnsOldestUpdatedAtOfTwoAggregators() public {
        MockAggregatorV3 aggregator0 = new MockAggregatorV3(8);
        MockAggregatorV3 aggregator1 = new MockAggregatorV3(8);
        vm.warp(2_000_000_000);
        aggregator0.setRound(1e8, 1_999_999_000);
        aggregator1.setRound(2e8, 1_999_998_000);

        ChainlinkOracle oracle =
            new ChainlinkOracle([address(aggregator0), address(aggregator1)], [uint48(1 days), uint48(1 days)]);
        (uint256 price, uint48 updatedAt) = oracle.getPriceData();
        assertEq(price, 2e18);
        assertEq(updatedAt, 1_999_998_000);
    }

    function testChainlinkOracleSingleAggregatorUpdatedAt() public {
        MockAggregatorV3 aggregator0 = new MockAggregatorV3(8);
        vm.warp(2_000_000_000);
        aggregator0.setRound(1e8, 1_999_999_123);

        ChainlinkOracle oracle = new ChainlinkOracle([address(aggregator0), address(0)], [uint48(1 days), uint48(0)]);
        (, uint48 updatedAt) = oracle.getPriceData();
        assertEq(updatedAt, 1_999_999_123);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IMidasDataFeed} from "../../src/interfaces/adapters/ll-adapter/midas/IMidasOracle.sol";

abstract contract MGlobalDataFeedHelper is Test {
    address internal constant MGLOBAL_DATA_FEED = address(0xBEEF);
    address internal constant MGLOBAL_MARKET_AGGREGATOR = 0x66Aa9fcD63DF74e1f67A9452E6E59Fbc67f75E38;

    function _mockMGlobalDataFeed() internal {
        vm.mockCall(MGLOBAL_DATA_FEED, abi.encodeCall(IMidasDataFeed.getDataInBase18, ()), abi.encode(1e18));
        vm.mockCall(
            MGLOBAL_DATA_FEED, abi.encodeCall(IMidasDataFeed.aggregator, ()), abi.encode(MGLOBAL_MARKET_AGGREGATOR)
        );
    }
}

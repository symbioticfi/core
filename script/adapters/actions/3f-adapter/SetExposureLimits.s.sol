// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetExposureLimitsBase.s.sol";

contract SetExposureLimitsScript is SetExposureLimitsBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    uint256 constant MIN_YIELD_PER_REQUEST = 0;
    uint256 constant MIN_ASSETS_PER_REQUEST = 1;
    uint256 constant MAX_ASSETS_PER_REQUEST = type(uint256).max;

    function run() public {
        runBase(ADAPTER, MIN_YIELD_PER_REQUEST, MIN_ASSETS_PER_REQUEST, MAX_ASSETS_PER_REQUEST);
    }
}

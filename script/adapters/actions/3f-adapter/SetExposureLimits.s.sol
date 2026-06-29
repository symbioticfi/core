// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetExposureLimitsBase.s.sol";

contract SetExposureLimitsScript is SetExposureLimitsBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    uint256 constant PER_REQUEST_MAX_COLLATERAL = 0;
    uint256 constant MIN_REQUEST_YIELD = 0;
    uint256 constant MAX_CONCURRENT_LOANS = 0;

    function run() public {
        runBase(ADAPTER, PER_REQUEST_MAX_COLLATERAL, MIN_REQUEST_YIELD, MAX_CONCURRENT_LOANS);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetPerformanceFeeBase.s.sol";

contract SetPerformanceFeeScript is SetPerformanceFeeBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    uint96 constant FEE = 0;
    address constant RECEIVER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(VAULT, FEE, RECEIVER);
    }
}

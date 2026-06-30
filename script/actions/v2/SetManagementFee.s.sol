// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetManagementFeeBase.s.sol";

contract SetManagementFeeScript is SetManagementFeeBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    uint96 constant FEE = 0;
    address constant RECEIVER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(VAULT, FEE, RECEIVER);
    }
}

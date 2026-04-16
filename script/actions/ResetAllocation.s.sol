// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/ResetAllocationBase.s.sol";

contract ResetAllocationScript is ResetAllocationBaseScript {
    address constant VAULT = address(0);
    bytes32 constant SUBNETWORK = bytes32(0);

    function run() public {
        runBase(VAULT, SUBNETWORK);
    }
}

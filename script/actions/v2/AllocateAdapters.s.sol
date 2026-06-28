// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/AllocateAdaptersBase.s.sol";

contract AllocateAdaptersScript is AllocateAdaptersBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    uint256 constant AMOUNT = 0;

    function run() public {
        runBase(VAULT, AMOUNT);
    }
}

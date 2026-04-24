// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/DeallocateAdaptersBase.s.sol";

contract DeallocateAdaptersScript is DeallocateAdaptersBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(VAULT);
    }
}

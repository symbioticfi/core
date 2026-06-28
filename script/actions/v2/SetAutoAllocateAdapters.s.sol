// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetAutoAllocateAdaptersBase.s.sol";

contract SetAutoAllocateAdaptersScript is SetAutoAllocateAdaptersBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;

    function run() public {
        address[] memory adapters = new address[](1);
        adapters[0] = ADAPTER;
        runBase(VAULT, adapters);
    }
}

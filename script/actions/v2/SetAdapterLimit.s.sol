// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetAdapterLimitBase.s.sol";

contract SetAdapterLimitScript is SetAdapterLimitBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    uint208 constant LIMIT = 0;

    function run() public {
        runBase(VAULT, ADAPTER, LIMIT);
    }
}

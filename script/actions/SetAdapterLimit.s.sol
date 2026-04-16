// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetAdapterLimitBase.s.sol";

contract SetAdapterLimitScript is SetAdapterLimitBaseScript {
    address constant VAULT = address(0);
    address constant ADAPTER = address(0);
    uint208 constant LIMIT = 0;

    function run() public {
        runBase(VAULT, ADAPTER, LIMIT);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetGlobalLimitBase.s.sol";

contract SetGlobalLimitScript is SetGlobalLimitBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant ASSET = 0x0000000000000000000000000000000000000000;
    uint256 constant LIMIT = 0;

    function run() public {
        runBase(ADAPTER, ASSET, LIMIT);
    }
}

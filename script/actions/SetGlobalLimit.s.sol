// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetGlobalLimitBase.s.sol";

contract SetGlobalLimitScript is SetGlobalLimitBaseScript {
    address constant ADAPTER = address(0);
    address constant ASSET = address(0);
    uint256 constant LIMIT = 0;

    function run() public {
        runBase(ADAPTER, ASSET, LIMIT);
    }
}

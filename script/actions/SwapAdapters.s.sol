// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SwapAdaptersBase.s.sol";

contract SwapAdaptersScript is SwapAdaptersBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    address constant ADAPTER1 = 0x0000000000000000000000000000000000000000;
    address constant ADAPTER2 = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(VAULT, ADAPTER1, ADAPTER2);
    }
}

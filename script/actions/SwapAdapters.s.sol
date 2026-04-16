// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SwapAdaptersBase.s.sol";

contract SwapAdaptersScript is SwapAdaptersBaseScript {
    address constant VAULT = address(0);
    address constant ADAPTER1 = address(0);
    address constant ADAPTER2 = address(0);

    function run() public {
        runBase(VAULT, ADAPTER1, ADAPTER2);
    }
}

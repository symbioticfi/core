// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SwapSlotsBase.s.sol";

contract SwapSlotsScript is SwapSlotsBaseScript {
    address constant DELEGATOR = 0x0000000000000000000000000000000000000000;
    uint64 constant INDEX1 = 0;
    uint64 constant INDEX2 = 0;

    function run() public {
        runBase(DELEGATOR, INDEX1, INDEX2);
    }
}

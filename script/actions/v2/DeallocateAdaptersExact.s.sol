// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/DeallocateAdaptersExactBase.s.sol";

contract DeallocateAdaptersExactScript is DeallocateAdaptersExactBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    uint256 constant AMOUNT = 0;

    function run() public {
        runBase(VAULT, AMOUNT);
    }
}

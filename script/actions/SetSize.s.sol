// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetSizeBase.s.sol";

contract SetSizeScript is SetSizeBaseScript {
    address constant DELEGATOR = address(0);
    uint96 constant INDEX = 0;
    uint128 constant SIZE = 0;

    function run() public {
        runBase(DELEGATOR, INDEX, SIZE);
    }
}

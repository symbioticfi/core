// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetUnpauserBase.s.sol";

contract SetUnpauserScript is SetUnpauserBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant UNPAUSER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER, UNPAUSER);
    }
}

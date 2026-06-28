// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/InvalidateConvertsBase.s.sol";

contract InvalidateConvertsScript is InvalidateConvertsBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant TOKEN_IN = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER, TOKEN_IN);
    }
}

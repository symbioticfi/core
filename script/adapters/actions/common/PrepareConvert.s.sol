// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/PrepareConvertBase.s.sol";

contract PrepareConvertScript is PrepareConvertBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant TOKEN_IN = 0x0000000000000000000000000000000000000000;
    uint256 constant AMOUNT_IN = 0;
    address constant TOKEN_OUT = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER, TOKEN_IN, AMOUNT_IN, TOKEN_OUT, "");
    }
}

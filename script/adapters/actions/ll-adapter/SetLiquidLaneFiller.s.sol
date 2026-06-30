// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetLiquidLaneFillerBase.s.sol";

contract SetLiquidLaneFillerScript is SetLiquidLaneFillerBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant FILLER = 0x0000000000000000000000000000000000000000;
    bool constant IS_AUTHORIZED = false;

    function run() public {
        runBase(ADAPTER, FILLER, IS_AUTHORIZED);
    }
}

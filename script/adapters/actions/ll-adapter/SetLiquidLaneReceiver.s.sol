// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetLiquidLaneReceiverBase.s.sol";

contract SetLiquidLaneReceiverScript is SetLiquidLaneReceiverBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant RECEIVER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER, RECEIVER);
    }
}

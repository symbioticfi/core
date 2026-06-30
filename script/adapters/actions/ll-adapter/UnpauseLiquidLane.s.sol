// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/UnpauseLiquidLaneBase.s.sol";

contract UnpauseLiquidLaneScript is UnpauseLiquidLaneBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER);
    }
}

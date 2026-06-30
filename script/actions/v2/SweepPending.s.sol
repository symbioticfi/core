// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SweepPendingBase.s.sol";

contract SweepPendingScript is SweepPendingBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(VAULT);
    }
}

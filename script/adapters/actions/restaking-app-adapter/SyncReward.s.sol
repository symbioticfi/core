// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SyncRewardBase.s.sol";

contract SyncRewardScript is SyncRewardBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER);
    }
}

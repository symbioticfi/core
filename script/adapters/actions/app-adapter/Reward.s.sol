// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RewardBase.s.sol";

contract RewardScript is RewardBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant TOKEN = 0x0000000000000000000000000000000000000000;
    uint256 constant AMOUNT = 0;

    function run() public {
        runBase(ADAPTER, TOKEN, AMOUNT);
    }
}

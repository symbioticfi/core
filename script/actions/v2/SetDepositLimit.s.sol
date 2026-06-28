// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetDepositLimitBase.s.sol";

contract SetDepositLimitScript is SetDepositLimitBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    uint256 constant LIMIT = 0;

    function run() public {
        runBase(VAULT, LIMIT);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetIsDepositLimitBase.s.sol";

contract SetIsDepositLimitScript is SetIsDepositLimitBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    bool constant STATUS = false;

    function run() public {
        runBase(VAULT, STATUS);
    }
}

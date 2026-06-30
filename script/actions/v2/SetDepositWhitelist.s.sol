// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetDepositWhitelistBase.s.sol";

contract SetDepositWhitelistScript is SetDepositWhitelistBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    bool constant STATUS = false;

    function run() public {
        runBase(VAULT, STATUS);
    }
}

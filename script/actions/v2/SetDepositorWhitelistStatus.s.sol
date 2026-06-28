// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetDepositorWhitelistStatusBase.s.sol";

contract SetDepositorWhitelistStatusScript is SetDepositorWhitelistStatusBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    address constant ACCOUNT = 0x0000000000000000000000000000000000000000;
    bool constant STATUS = false;

    function run() public {
        runBase(VAULT, ACCOUNT, STATUS);
    }
}

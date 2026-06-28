// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/ExecuteSlashBase.s.sol";

contract ExecuteSlashScript is ExecuteSlashBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    uint256 constant SLASH_INDEX = 0;

    function run() public {
        runBase(VAULT, SLASH_INDEX);
    }
}

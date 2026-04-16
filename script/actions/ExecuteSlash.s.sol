// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/ExecuteSlashBase.s.sol";

contract ExecuteSlashScript is ExecuteSlashBaseScript {
    address constant VAULT = address(0);
    uint256 constant SLASH_INDEX = 0;

    function run() public {
        runBase(VAULT, SLASH_INDEX);
    }
}

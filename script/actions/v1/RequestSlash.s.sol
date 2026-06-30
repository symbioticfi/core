// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RequestSlashBase.s.sol";

contract RequestSlashScript is RequestSlashBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    bytes32 constant SUBNETWORK = 0x0000000000000000000000000000000000000000000000000000000000000000;
    address constant OPERATOR = 0x0000000000000000000000000000000000000000;
    uint256 constant AMOUNT = 0;

    function run() public {
        runBase(VAULT, SUBNETWORK, OPERATOR, AMOUNT);
    }
}

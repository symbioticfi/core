// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RequestSlashBase.s.sol";

contract RequestSlashScript is RequestSlashBaseScript {
    address constant VAULT = address(0);
    bytes32 constant SUBNETWORK = bytes32(0);
    address constant OPERATOR = address(0);
    uint256 constant AMOUNT = 0;

    function run() public {
        runBase(VAULT, SUBNETWORK, OPERATOR, AMOUNT);
    }
}

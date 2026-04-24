// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SyncOwedSlashBase.s.sol";

contract SyncOwedSlashScript is SyncOwedSlashBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    bytes32 constant SUBNETWORK = 0x0000000000000000000000000000000000000000000000000000000000000000;
    address constant OPERATOR = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(VAULT, SUBNETWORK, OPERATOR);
    }
}

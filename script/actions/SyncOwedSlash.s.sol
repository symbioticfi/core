// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SyncOwedSlashBase.s.sol";

contract SyncOwedSlashScript is SyncOwedSlashBaseScript {
    address constant VAULT = address(0);
    bytes32 constant SUBNETWORK = bytes32(0);
    address constant OPERATOR = address(0);

    function run() public {
        runBase(VAULT, SUBNETWORK, OPERATOR);
    }
}

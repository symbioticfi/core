// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/CreateSlotBase.s.sol";

contract CreateSlotScript is CreateSlotBaseScript {
    address constant DELEGATOR = 0x0000000000000000000000000000000000000000;
    bytes32 constant SUBNETWORK = 0x0000000000000000000000000000000000000000000000000000000000000000;
    address constant OPERATOR = 0x0000000000000000000000000000000000000000;
    uint128 constant SIZE = 0;

    function run() public {
        runBase(DELEGATOR, SUBNETWORK, OPERATOR, SIZE);
    }
}

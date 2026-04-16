// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/CreateSlotBase.s.sol";

contract CreateSlotScript is CreateSlotBaseScript {
    address constant DELEGATOR = address(0);
    bytes32 constant SUBNETWORK_OR_OPERATOR = bytes32(0);
    uint96 constant PARENT_INDEX = 0;
    bool constant IS_SHARED = false;
    bool constant NO_ADAPTERS = false;
    uint128 constant SIZE = 0;

    function run() public {
        runBase(DELEGATOR, SUBNETWORK_OR_OPERATOR, PARENT_INDEX, IS_SHARED, NO_ADAPTERS, SIZE);
    }
}

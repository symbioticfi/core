// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RemoveSlotBase.s.sol";

contract RemoveSlotScript is RemoveSlotBaseScript {
    address constant DELEGATOR = 0x0000000000000000000000000000000000000000;
    uint32 constant INDEX = 0;

    function run() public {
        runBase(DELEGATOR, INDEX);
    }
}

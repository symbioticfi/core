// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/AllocateAdapterBase.s.sol";

contract AllocateAdapterScript is AllocateAdapterBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    uint256 constant AMOUNT = 0;

    function run() public {
        runBase(VAULT, ADAPTER, AMOUNT);
    }
}

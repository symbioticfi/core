// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/AllocateAdapterBase.s.sol";

contract AllocateAdapterScript is AllocateAdapterBaseScript {
    address constant VAULT = address(0);
    address constant ADAPTER = address(0);
    uint256 constant AMOUNT = 0;

    function run() public {
        runBase(VAULT, ADAPTER, AMOUNT);
    }
}

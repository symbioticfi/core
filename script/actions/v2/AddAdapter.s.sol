// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/AddAdapterBase.s.sol";

contract AddAdapterScript is AddAdapterBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(VAULT, ADAPTER);
    }
}

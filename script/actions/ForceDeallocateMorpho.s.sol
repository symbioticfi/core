// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/ForceDeallocateMorphoBase.s.sol";

contract ForceDeallocateMorphoScript is ForceDeallocateMorphoBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    uint256 constant AMOUNT = 0;

    function run() public {
        runBase(ADAPTER, VAULT, AMOUNT);
    }
}

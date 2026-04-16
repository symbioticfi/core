// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SkimAdaptersBase.s.sol";

contract SkimAdaptersScript is SkimAdaptersBaseScript {
    address constant VAULT = address(0);

    function run() public {
        runBase(VAULT);
    }
}

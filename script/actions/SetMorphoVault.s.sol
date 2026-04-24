// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetMorphoVaultBase.s.sol";

contract SetMorphoVaultScript is SetMorphoVaultBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    address constant MORPHO_VAULT = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER, VAULT, MORPHO_VAULT);
    }
}

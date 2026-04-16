// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetMorphoVaultBase.s.sol";

contract SetMorphoVaultScript is SetMorphoVaultBaseScript {
    address constant ADAPTER = address(0);
    address constant VAULT = address(0);
    address constant MORPHO_VAULT = address(0);

    function run() public {
        runBase(ADAPTER, VAULT, MORPHO_VAULT);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./SymbioticInit.sol";

contract SymbioticIntegration is SymbioticInit {
    address[] public tokens;

    address[] public vaults;
    Vm.Wallet[] public networks;
    Vm.Wallet[] public operators;
    Vm.Wallet[] public stakers;

    function setUp() public virtual override {
        super.setUp();

        tokens.push(_getToken());

        uint256 numberOfVaults = 20;
        uint256 numberOfNetworks = 40;
        uint256 numberOfOperators = 100;
        uint256 numberOfStakers = 200;

        for (uint256 i; i < numberOfVaults; i++) {
            vaults.push(_getVault(tokens[0]));
        }
    }
}

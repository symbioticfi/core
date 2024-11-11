// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SymbioticInit.sol";

contract SymbioticIntegration is SymbioticInit {
    address[] public tokens;

    address[] public vaults;
    Vm.Wallet[] public networks;
    Vm.Wallet[] public operators;
    Vm.Wallet[] public stakers;

    address[] public existingTokens;
    address[] public existingVaults;
    Vm.Wallet[] public existingNetworks;
    Vm.Wallet[] public existingOperators;

    uint256 public NUMBER_OF_VAULTS = 20;
    uint256 public NUMBER_OF_NETWORKS = 40;
    uint256 public NUMBER_OF_OPERATORS = 100;
    uint256 public NUMBER_OF_STAKERS = 200;

    bool public SIMULATION_WITH_WITHDRAWALS = true;

    function setUp() public virtual override {
        // vm.selectFork(vm.createFork(vm.rpcUrl("mainnet")));
        // SYMBIOTIC_CORE_PROJECT_ROOT = "";

        super.setUp();

        _loadPossibleTokens();

        _loadExistingEntities();
        if (USE_EXISTING_DEPLOYMENT) {
            _loadExistingTokens();
            _loadExistingVaults();
            _loadExistingNetworks();
            _loadExistingOperators();
        }

        _createEnvironment();
    }

    function _loadExistingEntities() internal {
        if (USE_EXISTING_DEPLOYMENT) {
            uint256 numberOfVaults = ISymbioticRegistry(symbioticCore.vaultFactory).totalEntities();
            for (uint256 i; i < numberOfVaults; ++i) {
                address vault = ISymbioticRegistry(symbioticCore.vaultFactory).entity(i);
                existingVaults.push(vault);
                existingTokens.push(ISymbioticVault(vault).collateral());
            }
            uint256 numberOfNetworks = ISymbioticRegistry(symbioticCore.networkRegistry).totalEntities();
            for (uint256 i; i < numberOfNetworks; ++i) {
                existingNetworks.push(
                    VmSafe.Wallet({
                        addr: ISymbioticRegistry(symbioticCore.networkRegistry).entity(i),
                        publicKeyX: 0,
                        publicKeyY: 0,
                        privateKey: 0
                    })
                );
            }
            uint256 numberOfOperators = ISymbioticRegistry(symbioticCore.operatorRegistry).totalEntities();
            for (uint256 i; i < numberOfOperators; ++i) {
                existingOperators.push(
                    VmSafe.Wallet({
                        addr: ISymbioticRegistry(symbioticCore.operatorRegistry).entity(i),
                        publicKeyX: 0,
                        publicKeyY: 0,
                        privateKey: 0
                    })
                );
            }
        }
    }

    function _loadPossibleTokens() internal {
        address[] memory supportedTokens = _getSupportedTokens_SymbioticCore();
        if (supportedTokens.length != 0) {
            for (uint256 i; i < supportedTokens.length; i++) {
                tokens.push(supportedTokens[i]);
            }
        } else {
            tokens.push(_getToken_SymbioticCore());
            tokens.push(_getFeeOnTransferToken_SymbioticCore());
        }
    }

    function _loadExistingTokens() internal {
        for (uint256 i; i < existingTokens.length; ++i) {
            if (!_contains_SymbioticCore(tokens, existingTokens[i])) {
                tokens.push(existingTokens[i]);
            }
        }
    }

    function _loadExistingVaults() internal {
        for (uint256 i; i < existingVaults.length; ++i) {
            if (!_contains_SymbioticCore(vaults, existingVaults[i])) {
                vaults.push(existingVaults[i]);
            }
        }
    }

    function _loadExistingNetworks() internal {
        for (uint256 i; i < existingNetworks.length; ++i) {
            if (!_contains_SymbioticCore(networks, existingNetworks[i])) {
                networks.push(existingNetworks[i]);
            }
        }
    }

    function _loadExistingOperators() internal {
        for (uint256 i; i < existingOperators.length; ++i) {
            if (!_contains_SymbioticCore(operators, existingOperators[i])) {
                operators.push(existingOperators[i]);
            }
        }
    }

    function _createEnvironment() internal {
        _createParties(NUMBER_OF_VAULTS, NUMBER_OF_NETWORKS, NUMBER_OF_OPERATORS, NUMBER_OF_STAKERS);

        if (SIMULATION_WITH_WITHDRAWALS) {}
    }

    function _createParties(
        uint256 numberOfVaults,
        uint256 numberOfNetworks,
        uint256 numberOfOperators,
        uint256 numberOfStakers
    ) internal {
        for (uint256 i; i < numberOfVaults; ++i) {
            vaults.push(_getVault_SymbioticCore(_chooseToken_SymbioticCore(tokens)));
        }
        for (uint256 i; i < numberOfNetworks; ++i) {
            networks.push(_getNetwork_SymbioticCore());
        }
        for (uint256 i; i < numberOfOperators; ++i) {
            operators.push(_getOperator_SymbioticCore());
        }
        for (uint256 i; i < numberOfStakers; ++i) {
            stakers.push(_getStaker_SymbioticCore(tokens));
        }
    }

    function test_Abc() public {
        console2.log(vm.getBlockTimestamp(), vm.getBlockNumber());
        _skipBlocks_SymbioticCore(36);
        console2.log(vm.getBlockTimestamp(), vm.getBlockNumber());
    }
}

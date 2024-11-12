// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SymbioticCoreInit.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SymbioticCoreIntegration is SymbioticCoreInit {
    using SymbioticSubnetwork for bytes32;
    using SymbioticSubnetwork for address;

    address[] public tokens;

    address[] public vaults;
    Vm.Wallet[] public networks;
    Vm.Wallet[] public operators;
    Vm.Wallet[] public stakers;

    address[] public existingTokens;
    address[] public existingVaults;
    Vm.Wallet[] public existingNetworks;
    Vm.Wallet[] public existingOperators;

    // allocated network stake
    mapping(bytes32 subnetwork => mapping(address vault => bool)) public isVaultForSubnetwork;
    mapping(bytes32 subnetwork => address[] vaults) public vaultsForSubnetwork;
    // fully opted in and has stake
    mapping(bytes32 subnetwork => mapping(address vault => mapping(address operator => bool))) public
        isConfirmedOperatorForSubnetwork;
    mapping(bytes32 subnetwork => mapping(address vault => address[] operators)) public confirmedOperatorsForSubnetwork;
    // only needs to opt into network (map be used to test opt-in with signature)
    mapping(bytes32 subnetwork => mapping(address vault => mapping(address operator => bool))) public
        isPossibleOperatorForSubnetwork;
    mapping(bytes32 subnetwork => mapping(address vault => address[] operators)) public possibleOperatorsForSubnetwork;

    uint256 public SYMBIOTIC_CORE_NUMBER_OF_VAULTS = 20;
    uint256 public SYMBIOTIC_CORE_NUMBER_OF_NETWORKS = 10;
    uint256 public SYMBIOTIC_CORE_NUMBER_OF_OPERATORS = 20;
    uint256 public SYMBIOTIC_CORE_NUMBER_OF_STAKERS = 30;

    uint256 public SYMBIOTIC_CORE_DEPOSIT_INTO_VAULT_CHANCE = 1; // lower -> higher probability
    uint256 public SYMBIOTIC_CORE_WITHDRAW_FROM_VAULT_CHANCE = 3;
    uint256 public SYMBIOTIC_CORE_MAX_NETWORK_LIMIT_CHANCE = 1;
    uint256 public SYMBIOTIC_CORE_DELEGATE_TO_NETWORK_CHANCE = 1;
    uint256 public SYMBIOTIC_CORE_DELEGATE_TO_OPERATOR_CHANCE = 1;
    uint256 public SYMBIOTIC_CORE_OPT_IN_TO_VAULT_CHANCE = 1;
    uint256 public SYMBIOTIC_CORE_OPT_IN_TO_NETWORK_CHANCE = 1;

    uint96[] public SYMBIOTIC_CORE_SUBNETWORKS = [0, 1, 2];

    function setUp() public virtual override {
        // vm.selectFork(vm.createFork(vm.rpcUrl("mainnet")));
        // SYMBIOTIC_CORE_PROJECT_ROOT = "";

        super.setUp();

        _loadPossibleTokens();

        _loadExistingEntities();
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            _loadExistingTokens();
            _loadExistingVaults();
            _loadExistingNetworks();
            _loadExistingOperators();
        }

        _createEnvironment();

        _loadDataForNetworks();
    }

    function _loadExistingEntities() internal virtual {
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
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

    function _loadPossibleTokens() internal virtual {
        // address[] memory supportedTokens = _getSupportedTokens_SymbioticCore();
        // if (supportedTokens.length != 0) {
        //     for (uint256 i; i < supportedTokens.length; i++) {
        //         tokens.push(supportedTokens[i]);
        //     }
        // } else {
        //     tokens.push(_getToken_SymbioticCore());
        //     tokens.push(_getFeeOnTransferToken_SymbioticCore());
        // }

        tokens.push(_getToken_SymbioticCore());
        tokens.push(_getFeeOnTransferToken_SymbioticCore());
    }

    function _loadExistingTokens() internal virtual {
        for (uint256 i; i < existingTokens.length; ++i) {
            if (!_contains_SymbioticCore(tokens, existingTokens[i])) {
                tokens.push(existingTokens[i]);
            }
        }
    }

    function _loadExistingVaults() internal virtual {
        for (uint256 i; i < existingVaults.length; ++i) {
            if (!_contains_SymbioticCore(vaults, existingVaults[i])) {
                vaults.push(existingVaults[i]);
            }
        }
    }

    function _loadExistingNetworks() internal virtual {
        for (uint256 i; i < existingNetworks.length; ++i) {
            if (!_contains_SymbioticCore(networks, existingNetworks[i])) {
                networks.push(existingNetworks[i]);
            }
        }
    }

    function _loadExistingOperators() internal virtual {
        for (uint256 i; i < existingOperators.length; ++i) {
            if (!_contains_SymbioticCore(operators, existingOperators[i])) {
                operators.push(existingOperators[i]);
            }
        }
    }

    function _createEnvironment() internal virtual {
        _createParties(
            SYMBIOTIC_CORE_NUMBER_OF_VAULTS,
            SYMBIOTIC_CORE_NUMBER_OF_NETWORKS,
            SYMBIOTIC_CORE_NUMBER_OF_OPERATORS,
            SYMBIOTIC_CORE_NUMBER_OF_STAKERS
        );

        _depositIntoVaults();
        _withdrawFromVaults();

        _setMaxNetworkLimits();
        _delegateToNetworks();
        _delegateToOperators();
        _optInOperators();
    }

    function _createParties(
        uint256 numberOfVaults,
        uint256 numberOfNetworks,
        uint256 numberOfOperators,
        uint256 numberOfStakers
    ) internal virtual {
        for (uint256 i; i < numberOfVaults; ++i) {
            vaults.push(_getVault_SymbioticCore(_chooseAddress_SymbioticCore(tokens)));
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

    function _depositIntoVaults() internal virtual {
        for (uint256 i; i < stakers.length; ++i) {
            for (uint256 j; j < vaults.length; ++j) {
                if (randomChoice_SymbioticCore(SYMBIOTIC_CORE_DEPOSIT_INTO_VAULT_CHANCE)) {
                    _stakerDepositRandom_SymbioticCore(stakers[i].addr, vaults[j]);
                }
            }
        }
    }

    function _withdrawFromVaults() internal virtual {
        for (uint256 i; i < stakers.length; ++i) {
            for (uint256 j; j < vaults.length; ++j) {
                if (randomChoice_SymbioticCore(SYMBIOTIC_CORE_WITHDRAW_FROM_VAULT_CHANCE)) {
                    _stakerWithdrawRandom_SymbioticCore(stakers[i].addr, vaults[j]);
                }
            }
        }
    }

    function _setMaxNetworkLimits() internal virtual {
        for (uint256 i; i < vaults.length; ++i) {
            for (uint256 j; j < networks.length; ++j) {
                for (uint256 k; k < SYMBIOTIC_CORE_SUBNETWORKS.length; ++k) {
                    if (randomChoice_SymbioticCore(SYMBIOTIC_CORE_MAX_NETWORK_LIMIT_CHANCE)) {
                        _networkSetMaxNetworkLimitRandom_SymbioticCore(
                            networks[j].addr, vaults[i], SYMBIOTIC_CORE_SUBNETWORKS[k]
                        );
                    }
                }
            }
        }
    }

    function _delegateToNetworks() internal virtual {
        for (uint256 i; i < vaults.length; ++i) {
            for (uint256 j; j < networks.length; ++j) {
                for (uint256 k; k < SYMBIOTIC_CORE_SUBNETWORKS.length; ++k) {
                    if (
                        _curatorDelegateNetworkHasRoles_SymbioticCore(
                            address(this), vaults[i], networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k])
                        )
                    ) {
                        if (randomChoice_SymbioticCore(SYMBIOTIC_CORE_DELEGATE_TO_NETWORK_CHANCE)) {
                            _curatorDelegateNetworkRandom_SymbioticCore(
                                address(this), vaults[i], networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k])
                            );
                        }
                        continue;
                    }

                    if (
                        _curatorDelegateNetworkHasRoles_SymbioticCore(
                            Ownable(vaults[i]).owner(),
                            vaults[i],
                            networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k])
                        )
                    ) {
                        if (randomChoice_SymbioticCore(SYMBIOTIC_CORE_DELEGATE_TO_NETWORK_CHANCE)) {
                            _curatorDelegateNetworkRandom_SymbioticCore(
                                Ownable(vaults[i]).owner(),
                                vaults[i],
                                networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k])
                            );
                        }
                    }
                }
            }
        }
    }

    function _delegateToOperators() internal virtual {
        for (uint256 i; i < vaults.length; ++i) {
            for (uint256 j; j < networks.length; ++j) {
                for (uint256 k; k < SYMBIOTIC_CORE_SUBNETWORKS.length; ++k) {
                    for (uint256 l; l < operators.length; ++l) {
                        if (
                            _curatorDelegateOperatorHasRoles_SymbioticCore(
                                address(this),
                                vaults[i],
                                networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k]),
                                operators[l].addr
                            )
                        ) {
                            if (randomChoice_SymbioticCore(SYMBIOTIC_CORE_DELEGATE_TO_OPERATOR_CHANCE)) {
                                _curatorDelegateOperatorRandom_SymbioticCore(
                                    address(this),
                                    vaults[i],
                                    networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k]),
                                    operators[l].addr
                                );
                            }
                            continue;
                        }

                        if (
                            _curatorDelegateOperatorHasRoles_SymbioticCore(
                                Ownable(vaults[i]).owner(),
                                vaults[i],
                                networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k]),
                                operators[l].addr
                            )
                        ) {
                            if (randomChoice_SymbioticCore(SYMBIOTIC_CORE_DELEGATE_TO_OPERATOR_CHANCE)) {
                                _curatorDelegateOperatorRandom_SymbioticCore(
                                    Ownable(vaults[i]).owner(),
                                    vaults[i],
                                    networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k]),
                                    operators[l].addr
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    function _optInOperators() internal virtual {
        _optInOperatorsVauls();
        _optInOperatorsNetworks();
    }

    function _optInOperatorsVauls() internal virtual {
        for (uint256 i; i < vaults.length; ++i) {
            for (uint256 j; j < operators.length; ++j) {
                if (randomChoice_SymbioticCore(SYMBIOTIC_CORE_OPT_IN_TO_VAULT_CHANCE)) {
                    _operatorOptInWeak_SymbioticCore(operators[j].addr, vaults[i]);
                }
            }
        }
    }

    function _optInOperatorsNetworks() internal virtual {
        for (uint256 i; i < networks.length; ++i) {
            for (uint256 j; j < networks.length; ++j) {
                if (randomChoice_SymbioticCore(SYMBIOTIC_CORE_OPT_IN_TO_NETWORK_CHANCE)) {
                    _operatorOptInWeak_SymbioticCore(operators[j].addr, networks[i].addr);
                }
            }
        }
    }

    function _loadDataForNetworks() internal virtual {
        for (uint256 i; i < networks.length; ++i) {
            for (uint256 j; j < SYMBIOTIC_CORE_SUBNETWORKS.length; ++j) {
                bytes32 subnetwork = networks[i].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[j]);
                for (uint256 k; k < vaults.length; ++k) {
                    if (_vaultValidating_SymbioticCore(vaults[k], subnetwork)) {
                        isVaultForSubnetwork[subnetwork][vaults[k]] = true;
                        vaultsForSubnetwork[subnetwork].push(vaults[k]);
                    }

                    for (uint256 l; l < operators.length; ++l) {
                        if (_operatorPossibleValidating_SymbioticCore(operators[l].addr, vaults[k], subnetwork)) {
                            isPossibleOperatorForSubnetwork[subnetwork][vaults[k]][operators[l].addr] = true;
                            possibleOperatorsForSubnetwork[subnetwork][vaults[k]].push(operators[l].addr);
                        }
                        if (_operatorConfirmedValidating_SymbioticCore(operators[l].addr, vaults[k], subnetwork)) {
                            isConfirmedOperatorForSubnetwork[subnetwork][vaults[k]][operators[l].addr] = true;
                            confirmedOperatorsForSubnetwork[subnetwork][vaults[k]].push(operators[l].addr);
                        }
                    }
                }
            }
        }
    }

    // function test_Test() public {
    //     address network = networks[0].addr;
    //     uint96 identifier = SYMBIOTIC_CORE_SUBNETWORKS[0];
    //     address collateral = tokens[0];
    //     bytes32 subnetwork = network.subnetwork(identifier);

    //     for (uint256 i; i < vaultsForSubnetwork[subnetwork].length; ++i) {
    //         address vault = vaultsForSubnetwork[subnetwork][i];
    //         console2.log("Vault:", vault);
    //     }

    //     for (uint256 i; i < vaultsForSubnetwork[subnetwork].length; ++i) {
    //         address vault = vaultsForSubnetwork[subnetwork][i];
    //         if (ISymbioticVault(vault).collateral() == collateral) {
    //             for (uint256 j; j < confirmedOperatorsForSubnetwork[subnetwork][vault].length; ++j) {
    //                 address operator = confirmedOperatorsForSubnetwork[subnetwork][vault][j];
    //                 console2.log("Vault/Operator:", vault, operator);
    //             }
    //         }
    //     }

    //     address vault = vaultsForSubnetwork[subnetwork][0];
    //     Vm.Wallet memory newOperator = _getOperatorWithOptIns_SymbioticCore(vault, network);
    //     _curatorDelegateRandom_SymbioticCore(address(this), vault, subnetwork, newOperator.addr);

    //     console2.log(
    //         "Stake before new staker:",
    //         ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).stake(subnetwork, newOperator.addr)
    //     );
    //     console2.log("Total stake before new staker:", ISymbioticVault(vault).totalStake());

    //     Vm.Wallet memory newStaker = _getStakerWithStake_SymbioticCore(tokens, vault);

    //     console2.log(
    //         "Stake after new staker:",
    //         ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).stake(subnetwork, newOperator.addr)
    //     );
    //     console2.log("Total stake after new staker:", ISymbioticVault(vault).totalStake());
    //     console2.log("User stake:", ISymbioticVault(vault).slashableBalanceOf(newStaker.addr));
    // }
}

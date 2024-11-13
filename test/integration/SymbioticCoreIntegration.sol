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
        super.setUp();

        _addPossibleTokens();

        _loadExistingEntities();
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            _addExistingEntities();
        }

        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            _createStakers(SYMBIOTIC_CORE_NUMBER_OF_STAKERS);
        } else {
            _createEnvironment();
        }

        _addDataForNetworks();
    }

    function _loadExistingEntities() internal virtual {
        _loadExistingVaultsAndTokens();
        _loadExistingNetworks();
        _loadExistingOperators();
    }

    function _loadExistingVaultsAndTokens() internal virtual {
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            uint256 numberOfVaults = ISymbioticRegistry(symbioticCore.vaultFactory).totalEntities();
            for (uint256 i; i < numberOfVaults; ++i) {
                address vault = ISymbioticRegistry(symbioticCore.vaultFactory).entity(i);
                existingVaults.push(vault);
                address collateral = ISymbioticVault(vault).collateral();
                if (!_contains_SymbioticCore(existingTokens, collateral)) {
                    existingTokens.push(collateral);
                }
            }
        }
    }

    function _loadExistingNetworks() internal virtual {
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
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
        }
    }

    function _loadExistingOperators() internal virtual {
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
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

    function _addPossibleTokens() internal virtual {
        address[] memory supportedTokens = _getSupportedTokens_SymbioticCore();
        for (uint256 i; i < supportedTokens.length; i++) {
            if (_supportsDeal_SymbioticCore(supportedTokens[i])) {
                tokens.push(supportedTokens[i]);
            }
        }
        if (!SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            tokens.push(_getToken_SymbioticCore());
            tokens.push(_getFeeOnTransferToken_SymbioticCore());
        }
    }

    function _addExistingEntities() internal virtual {
        _addExistingTokens();
        _addExistingVaults();
        _addExistingNetworks();
        _addExistingOperators();
    }

    function _addExistingTokens() internal virtual {
        for (uint256 i; i < existingTokens.length; ++i) {
            if (!_contains_SymbioticCore(tokens, existingTokens[i]) && _supportsDeal_SymbioticCore(existingTokens[i])) {
                tokens.push(existingTokens[i]);
            }
        }
    }

    function _addExistingVaults() internal virtual {
        for (uint256 i; i < existingVaults.length; ++i) {
            address collateral = ISymbioticVault(existingVaults[i]).collateral();
            if (
                !_contains_SymbioticCore(vaults, existingVaults[i]) && _supportsDeal_SymbioticCore(collateral)
                    && ISymbioticVault(existingVaults[i]).isInitialized()
            ) {
                vaults.push(existingVaults[i]);
            }
        }
    }

    function _addExistingNetworks() internal virtual {
        for (uint256 i; i < existingNetworks.length; ++i) {
            if (!_contains_SymbioticCore(networks, existingNetworks[i])) {
                networks.push(existingNetworks[i]);
            }
        }
    }

    function _addExistingOperators() internal virtual {
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
        _createNetworks(numberOfNetworks);
        _createOperators(numberOfOperators);
        _createVaults(numberOfVaults);
        _createStakers(numberOfStakers);
    }

    function _createNetworks(
        uint256 numberOfNetworks
    ) internal virtual {
        for (uint256 i; i < numberOfNetworks; ++i) {
            networks.push(_getNetwork_SymbioticCore());
        }
    }

    function _createOperators(
        uint256 numberOfOperators
    ) internal virtual {
        for (uint256 i; i < numberOfOperators; ++i) {
            operators.push(_getOperator_SymbioticCore());
        }
    }

    function _createVaults(
        uint256 numberOfVaults
    ) internal virtual {
        for (uint256 i; i < numberOfVaults; ++i) {
            vaults.push(
                _getVaultRandom_SymbioticCore(vmWalletsToAddresses(operators), _randomPick_SymbioticCore(tokens))
            );
        }
    }

    function _createStakers(
        uint256 numberOfStakers
    ) internal virtual {
        for (uint256 i; i < numberOfStakers; ++i) {
            stakers.push(_getStaker_SymbioticCore(tokens));
        }
    }

    function _depositIntoVaults() internal virtual {
        for (uint256 i; i < stakers.length; ++i) {
            for (uint256 j; j < vaults.length; ++j) {
                if (_randomChoice_SymbioticCore(SYMBIOTIC_CORE_DEPOSIT_INTO_VAULT_CHANCE)) {
                    _stakerDepositRandom_SymbioticCore(stakers[i].addr, vaults[j]);
                }
            }
        }
    }

    function _withdrawFromVaults() internal virtual {
        for (uint256 i; i < stakers.length; ++i) {
            for (uint256 j; j < vaults.length; ++j) {
                if (_randomChoice_SymbioticCore(SYMBIOTIC_CORE_WITHDRAW_FROM_VAULT_CHANCE)) {
                    _stakerWithdrawRandom_SymbioticCore(stakers[i].addr, vaults[j]);
                }
            }
        }
    }

    function _setMaxNetworkLimits() internal virtual {
        for (uint256 i; i < vaults.length; ++i) {
            for (uint256 j; j < networks.length; ++j) {
                for (uint256 k; k < SYMBIOTIC_CORE_SUBNETWORKS.length; ++k) {
                    if (_randomChoice_SymbioticCore(SYMBIOTIC_CORE_MAX_NETWORK_LIMIT_CHANCE)) {
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
                    if (_randomChoice_SymbioticCore(SYMBIOTIC_CORE_DELEGATE_TO_NETWORK_CHANCE)) {
                        _delegateToNetworkTry(vaults[i], networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k]));
                    }
                }
            }
        }
    }

    function _delegateToNetworkTry(address vault, bytes32 subnetwork) internal virtual returns (bool success) {
        (, success) = _delegateToNetworkInternal(Ownable(vault).owner(), vault, subnetwork);
    }

    function _delegateToNetworkInternal(
        address curator,
        address vault,
        bytes32 subnetwork
    ) internal virtual returns (bool curatorFound, bool success) {
        if (_curatorDelegateNetworkHasRoles_SymbioticCore(curator, vault, subnetwork)) {
            success = _curatorDelegateNetworkRandom_SymbioticCore(curator, vault, subnetwork);
            return (true, success);
        }
        return (false, false);
    }

    function _delegateToOperators() internal virtual {
        for (uint256 i; i < vaults.length; ++i) {
            for (uint256 j; j < networks.length; ++j) {
                for (uint256 k; k < SYMBIOTIC_CORE_SUBNETWORKS.length; ++k) {
                    for (uint256 l; l < operators.length; ++l) {
                        if (_randomChoice_SymbioticCore(SYMBIOTIC_CORE_DELEGATE_TO_OPERATOR_CHANCE)) {
                            _delegateToOperatorTry(
                                vaults[i], networks[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k]), operators[l].addr
                            );
                        }
                    }
                }
            }
        }
    }

    function _delegateToOperatorTry(
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool success) {
        (, success) = _delegateToOperatorInternal(Ownable(vault).owner(), vault, subnetwork, operator);
    }

    function _delegateToOperatorInternal(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool curatorFound, bool success) {
        if (_curatorDelegateOperatorHasRoles_SymbioticCore(curator, vault, subnetwork, operator)) {
            success = _curatorDelegateOperatorRandom_SymbioticCore(curator, vault, subnetwork, operator);
            return (true, success);
        }
        return (false, false);
    }

    function _delegateTry(address vault, bytes32 subnetwork, address operator) internal virtual returns (bool) {
        return _delegateToNetworkTry(vault, subnetwork) && _delegateToOperatorTry(vault, subnetwork, operator);
    }

    function _optInOperators() internal virtual {
        _optInOperatorsVaults();
        _optInOperatorsNetworks();
    }

    function _optInOperatorsVaults() internal virtual {
        for (uint256 i; i < vaults.length; ++i) {
            for (uint256 j; j < operators.length; ++j) {
                if (_randomChoice_SymbioticCore(SYMBIOTIC_CORE_OPT_IN_TO_VAULT_CHANCE)) {
                    _operatorOptInWeak_SymbioticCore(operators[j].addr, vaults[i]);
                }
            }
        }
    }

    function _optInOperatorsNetworks() internal virtual {
        for (uint256 i; i < networks.length; ++i) {
            for (uint256 j; j < networks.length; ++j) {
                if (_randomChoice_SymbioticCore(SYMBIOTIC_CORE_OPT_IN_TO_NETWORK_CHANCE)) {
                    _operatorOptInWeak_SymbioticCore(operators[j].addr, networks[i].addr);
                }
            }
        }
    }

    function _addDataForNetworks() internal virtual {
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
}

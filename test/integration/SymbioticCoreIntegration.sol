// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SymbioticCoreInit.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SymbioticCoreIntegration is SymbioticCoreInit {
    using SymbioticSubnetwork for bytes32;
    using SymbioticSubnetwork for address;

    address[] public tokens_SymbioticCore;

    address[] public vaults_SymbioticCore;
    Vm.Wallet[] public networks_SymbioticCore;
    Vm.Wallet[] public operators_SymbioticCore;
    Vm.Wallet[] public stakers_SymbioticCore;

    address[] public existingTokens_SymbioticCore;
    address[] public existingVaults_SymbioticCore;
    Vm.Wallet[] public existingNetworks_SymbioticCore;
    Vm.Wallet[] public existingOperators_SymbioticCore;

    // allocated network stake
    mapping(bytes32 subnetwork => mapping(address vault => bool)) public isVaultForSubnetwork;
    mapping(bytes32 subnetwork => address[] vaults_SymbioticCore) public vaultsForSubnetwork;
    // fully opted in and has stake
    mapping(bytes32 subnetwork => mapping(address vault => mapping(address operator => bool))) public
        isConfirmedOperatorForSubnetwork;
    mapping(bytes32 subnetwork => mapping(address vault => address[] operators)) public confirmedOperatorsForSubnetwork;
    // only needs to opt into network (may be used to test opt-in with signature)
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

    uint96[] public SYMBIOTIC_CORE_SUBNETWORKS = [0, 1];

    function setUp() public virtual override {
        SymbioticCoreInit.setUp();

        _addPossibleTokens_SymbioticCore();

        _loadExistingEntities_SymbioticCore();
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            _addExistingEntities_SymbioticCore();
        }

        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            _createStakers_SymbioticCore(SYMBIOTIC_CORE_NUMBER_OF_STAKERS);
        } else {
            _createEnvironment_SymbioticCore();
        }

        _addDataForNetworks_SymbioticCore();
    }

    function _loadExistingEntities_SymbioticCore() internal virtual {
        _loadExistingVaultsAndTokens_SymbioticCore();
        _loadExistingNetworks_SymbioticCore();
        _loadExistingOperators_SymbioticCore();
    }

    function _loadExistingVaultsAndTokens_SymbioticCore() internal virtual {
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            uint256 numberOfVaults = symbioticCore.vaultFactory.totalEntities();
            for (uint256 i; i < numberOfVaults; ++i) {
                address vault = symbioticCore.vaultFactory.entity(i);
                existingVaults_SymbioticCore.push(vault);
                address collateral = ISymbioticVault(vault).collateral();
                if (!_contains_Symbiotic(existingTokens_SymbioticCore, collateral)) {
                    existingTokens_SymbioticCore.push(collateral);
                }
            }
        }
    }

    function _loadExistingNetworks_SymbioticCore() internal virtual {
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            uint256 numberOfNetworks = symbioticCore.networkRegistry.totalEntities();
            for (uint256 i; i < numberOfNetworks; ++i) {
                existingNetworks_SymbioticCore.push(
                    _createWalletByAddress_Symbiotic(symbioticCore.networkRegistry.entity(i))
                );
            }
        }
    }

    function _loadExistingOperators_SymbioticCore() internal virtual {
        if (SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            uint256 numberOfOperators = symbioticCore.operatorRegistry.totalEntities();
            for (uint256 i; i < numberOfOperators; ++i) {
                existingOperators_SymbioticCore.push(
                    _createWalletByAddress_Symbiotic(symbioticCore.operatorRegistry.entity(i))
                );
            }
        }
    }

    function _addPossibleTokens_SymbioticCore() internal virtual {
        address[] memory supportedTokens = _getSupportedTokens_SymbioticCore();
        for (uint256 i; i < supportedTokens.length; ++i) {
            if (_supportsDeal_Symbiotic(supportedTokens[i])) {
                tokens_SymbioticCore.push(supportedTokens[i]);
            }
        }
        if (!SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT) {
            tokens_SymbioticCore.push(_getToken_SymbioticCore());
            tokens_SymbioticCore.push(_getFeeOnTransferToken_SymbioticCore());
        }
    }

    function _addExistingEntities_SymbioticCore() internal virtual {
        _addExistingTokens_SymbioticCore();
        _addExistingVaults_SymbioticCore();
        _addExistingNetworks_SymbioticCore();
        _addExistingOperators_SymbioticCore();
    }

    function _addExistingTokens_SymbioticCore() internal virtual {
        for (uint256 i; i < existingTokens_SymbioticCore.length; ++i) {
            if (
                !_contains_Symbiotic(tokens_SymbioticCore, existingTokens_SymbioticCore[i])
                    && _supportsDeal_Symbiotic(existingTokens_SymbioticCore[i])
            ) {
                tokens_SymbioticCore.push(existingTokens_SymbioticCore[i]);
            }
        }
    }

    function _addExistingVaults_SymbioticCore() internal virtual {
        for (uint256 i; i < existingVaults_SymbioticCore.length; ++i) {
            address collateral = ISymbioticVault(existingVaults_SymbioticCore[i]).collateral();
            if (
                !_contains_Symbiotic(vaults_SymbioticCore, existingVaults_SymbioticCore[i])
                    && _supportsDeal_Symbiotic(collateral)
                    && ISymbioticVault(existingVaults_SymbioticCore[i]).isInitialized()
            ) {
                vaults_SymbioticCore.push(existingVaults_SymbioticCore[i]);
            }
        }
    }

    function _addExistingNetworks_SymbioticCore() internal virtual {
        for (uint256 i; i < existingNetworks_SymbioticCore.length; ++i) {
            if (!_contains_Symbiotic(networks_SymbioticCore, existingNetworks_SymbioticCore[i])) {
                networks_SymbioticCore.push(existingNetworks_SymbioticCore[i]);
            }
        }
    }

    function _addExistingOperators_SymbioticCore() internal virtual {
        for (uint256 i; i < existingOperators_SymbioticCore.length; ++i) {
            if (!_contains_Symbiotic(operators_SymbioticCore, existingOperators_SymbioticCore[i])) {
                operators_SymbioticCore.push(existingOperators_SymbioticCore[i]);
            }
        }
    }

    function _createEnvironment_SymbioticCore() internal virtual {
        _createParties_SymbioticCore(
            SYMBIOTIC_CORE_NUMBER_OF_VAULTS,
            SYMBIOTIC_CORE_NUMBER_OF_NETWORKS,
            SYMBIOTIC_CORE_NUMBER_OF_OPERATORS,
            SYMBIOTIC_CORE_NUMBER_OF_STAKERS
        );

        _depositIntoVaults_SymbioticCore();
        _withdrawFromVaults_SymbioticCore();

        _setMaxNetworkLimits_SymbioticCore();
        _delegateToNetworks_SymbioticCore();
        _delegateToOperators_SymbioticCore();
        _optInOperators_SymbioticCore();
    }

    function _createParties_SymbioticCore(
        uint256 numberOfVaults,
        uint256 numberOfNetworks,
        uint256 numberOfOperators,
        uint256 numberOfStakers
    ) internal virtual {
        _createNetworks_SymbioticCore(numberOfNetworks);
        _createOperators_SymbioticCore(numberOfOperators);
        _createVaults_SymbioticCore(numberOfVaults);
        _createStakers_SymbioticCore(numberOfStakers);
    }

    function _createNetworks_SymbioticCore(
        uint256 numberOfNetworks
    ) internal virtual {
        for (uint256 i; i < numberOfNetworks; ++i) {
            networks_SymbioticCore.push(_getNetwork_SymbioticCore());
        }
    }

    function _createOperators_SymbioticCore(
        uint256 numberOfOperators
    ) internal virtual {
        for (uint256 i; i < numberOfOperators; ++i) {
            operators_SymbioticCore.push(_getOperator_SymbioticCore());
        }
    }

    function _createVaults_SymbioticCore(
        uint256 numberOfVaults
    ) internal virtual {
        for (uint256 i; i < numberOfVaults; ++i) {
            vaults_SymbioticCore.push(
                _getVaultRandom_SymbioticCore(
                    _vmWalletsToAddresses_Symbiotic(operators_SymbioticCore),
                    _randomPick_Symbiotic(tokens_SymbioticCore)
                )
            );
        }
    }

    function _createStakers_SymbioticCore(
        uint256 numberOfStakers
    ) internal virtual {
        for (uint256 i; i < numberOfStakers; ++i) {
            stakers_SymbioticCore.push(_getStaker_SymbioticCore(tokens_SymbioticCore));
        }
    }

    function _depositIntoVaults_SymbioticCore() internal virtual {
        for (uint256 i; i < stakers_SymbioticCore.length; ++i) {
            for (uint256 j; j < vaults_SymbioticCore.length; ++j) {
                if (_randomChoice_Symbiotic(SYMBIOTIC_CORE_DEPOSIT_INTO_VAULT_CHANCE)) {
                    _stakerDepositRandom_SymbioticCore(stakers_SymbioticCore[i].addr, vaults_SymbioticCore[j]);
                }
            }
        }
    }

    function _withdrawFromVaults_SymbioticCore() internal virtual {
        for (uint256 i; i < stakers_SymbioticCore.length; ++i) {
            for (uint256 j; j < vaults_SymbioticCore.length; ++j) {
                if (_randomChoice_Symbiotic(SYMBIOTIC_CORE_WITHDRAW_FROM_VAULT_CHANCE)) {
                    _stakerWithdrawRandom_SymbioticCore(stakers_SymbioticCore[i].addr, vaults_SymbioticCore[j]);
                }
            }
        }
    }

    function _setMaxNetworkLimits_SymbioticCore() internal virtual {
        for (uint256 i; i < vaults_SymbioticCore.length; ++i) {
            for (uint256 j; j < networks_SymbioticCore.length; ++j) {
                for (uint256 k; k < SYMBIOTIC_CORE_SUBNETWORKS.length; ++k) {
                    if (_randomChoice_Symbiotic(SYMBIOTIC_CORE_MAX_NETWORK_LIMIT_CHANCE)) {
                        _networkSetMaxNetworkLimitRandom_SymbioticCore(
                            networks_SymbioticCore[j].addr, vaults_SymbioticCore[i], SYMBIOTIC_CORE_SUBNETWORKS[k]
                        );
                    }
                }
            }
        }
    }

    function _delegateToNetworks_SymbioticCore() internal virtual {
        for (uint256 i; i < vaults_SymbioticCore.length; ++i) {
            for (uint256 j; j < networks_SymbioticCore.length; ++j) {
                for (uint256 k; k < SYMBIOTIC_CORE_SUBNETWORKS.length; ++k) {
                    if (_randomChoice_Symbiotic(SYMBIOTIC_CORE_DELEGATE_TO_NETWORK_CHANCE)) {
                        _delegateToNetworkTry_SymbioticCore(
                            vaults_SymbioticCore[i],
                            networks_SymbioticCore[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k])
                        );
                    }
                }
            }
        }
    }

    function _delegateToNetworkTry_SymbioticCore(
        address vault,
        bytes32 subnetwork
    ) internal virtual returns (bool success) {
        (, success) = _curatorDelegateToNetworkInternal_SymbioticCore(Ownable(vault).owner(), vault, subnetwork);
    }

    function _delegateToOperators_SymbioticCore() internal virtual {
        for (uint256 i; i < vaults_SymbioticCore.length; ++i) {
            for (uint256 j; j < networks_SymbioticCore.length; ++j) {
                for (uint256 k; k < SYMBIOTIC_CORE_SUBNETWORKS.length; ++k) {
                    for (uint256 l; l < operators_SymbioticCore.length; ++l) {
                        if (_randomChoice_Symbiotic(SYMBIOTIC_CORE_DELEGATE_TO_OPERATOR_CHANCE)) {
                            _delegateToOperatorTry_SymbioticCore(
                                vaults_SymbioticCore[i],
                                networks_SymbioticCore[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k]),
                                operators_SymbioticCore[l].addr
                            );
                        }
                    }
                }
            }
        }
    }

    function _delegateToOperatorTry_SymbioticCore(
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool success) {
        (, success) =
            _curatorDelegateToOperatorInternal_SymbioticCore(Ownable(vault).owner(), vault, subnetwork, operator);
    }

    function _delegateTry_SymbioticCore(
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool) {
        return _delegateToNetworkTry_SymbioticCore(vault, subnetwork)
            && _delegateToOperatorTry_SymbioticCore(vault, subnetwork, operator);
    }

    function _optInOperators_SymbioticCore() internal virtual {
        _optInOperatorsVaults_SymbioticCore();
        _optInOperatorsNetworks_SymbioticCore();
    }

    function _optInOperatorsVaults_SymbioticCore() internal virtual {
        for (uint256 i; i < vaults_SymbioticCore.length; ++i) {
            for (uint256 j; j < operators_SymbioticCore.length; ++j) {
                if (_randomChoice_Symbiotic(SYMBIOTIC_CORE_OPT_IN_TO_VAULT_CHANCE)) {
                    _operatorOptInWeak_SymbioticCore(operators_SymbioticCore[j].addr, vaults_SymbioticCore[i]);
                }
            }
        }
    }

    function _optInOperatorsNetworks_SymbioticCore() internal virtual {
        for (uint256 i; i < networks_SymbioticCore.length; ++i) {
            for (uint256 j; j < operators_SymbioticCore.length; ++j) {
                if (_randomChoice_Symbiotic(SYMBIOTIC_CORE_OPT_IN_TO_NETWORK_CHANCE)) {
                    _operatorOptInWeak_SymbioticCore(operators_SymbioticCore[j].addr, networks_SymbioticCore[i].addr);
                }
            }
        }
    }

    function _addDataForNetworks_SymbioticCore() internal virtual {
        for (uint256 i; i < networks_SymbioticCore.length; ++i) {
            for (uint256 j; j < SYMBIOTIC_CORE_SUBNETWORKS.length; ++j) {
                bytes32 subnetwork = networks_SymbioticCore[i].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[j]);
                for (uint256 k; k < vaults_SymbioticCore.length; ++k) {
                    if (_vaultValidating_SymbioticCore(vaults_SymbioticCore[k], subnetwork)) {
                        isVaultForSubnetwork[subnetwork][vaults_SymbioticCore[k]] = true;
                        vaultsForSubnetwork[subnetwork].push(vaults_SymbioticCore[k]);
                    }

                    for (uint256 l; l < operators_SymbioticCore.length; ++l) {
                        if (
                            _operatorPossibleValidating_SymbioticCore(
                                operators_SymbioticCore[l].addr, vaults_SymbioticCore[k], subnetwork
                            )
                        ) {
                            isPossibleOperatorForSubnetwork[subnetwork][vaults_SymbioticCore[k]][operators_SymbioticCore[l]
                                .addr] = true;
                            possibleOperatorsForSubnetwork[subnetwork][vaults_SymbioticCore[k]].push(
                                operators_SymbioticCore[l].addr
                            );
                        }
                        if (
                            _operatorConfirmedValidating_SymbioticCore(
                                operators_SymbioticCore[l].addr, vaults_SymbioticCore[k], subnetwork
                            )
                        ) {
                            isConfirmedOperatorForSubnetwork[subnetwork][vaults_SymbioticCore[k]][operators_SymbioticCore[l]
                                .addr] = true;
                            confirmedOperatorsForSubnetwork[subnetwork][vaults_SymbioticCore[k]].push(
                                operators_SymbioticCore[l].addr
                            );
                        }
                    }
                }
            }
        }
    }
}

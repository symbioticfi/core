// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SymbioticCoreIntegration.sol";

import {console2} from "forge-std/Test.sol";

contract SymbioticCoreIntegrationExample is SymbioticCoreIntegration {
    using SymbioticSubnetwork for bytes32;
    using SymbioticSubnetwork for address;

    address[] public networkVaults;

    address[] public confirmedNetworkVaults;
    mapping(address vault => address[]) public confirmedNetworkOperators;
    mapping(address vault => bytes32[]) public neighborNetworks;

    uint256 public SELECT_OPERATOR_CHANCE = 1; // lower -> higher probability

    function setUp() public override {
        SYMBIOTIC_CORE_PROJECT_ROOT = "";
        // vm.selectFork(vm.createFork(vm.rpcUrl("holesky")));
        // SYMBIOTIC_INIT_BLOCK = 2_727_202;
        // SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT = true;

        SYMBIOTIC_CORE_NUMBER_OF_STAKERS = 10;

        super.setUp();
    }

    function test_Network() public {
        address middleware = address(111);
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);
        uint96 identifier = 0;
        address collateral = tokens_SymbioticCore[0];
        bytes32 subnetwork = network.addr.subnetwork(identifier);

        console2.log("Network:", network.addr);
        console2.log("Identifier:", identifier);
        console2.log("Collateral:", collateral);

        for (uint256 i; i < vaults_SymbioticCore.length; ++i) {
            if (ISymbioticVault(vaults_SymbioticCore[i]).collateral() == collateral) {
                networkVaults.push(vaults_SymbioticCore[i]);
            }
        }

        console2.log("Network Vaults:", networkVaults.length);

        for (uint256 i; i < networkVaults.length; ++i) {
            _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, networkVaults[i], identifier);
            if (_delegateToNetworkTry_SymbioticCore(networkVaults[i], subnetwork)) {
                confirmedNetworkVaults.push(networkVaults[i]);
            }
        }

        console2.log("Confirmed Network Vaults:", confirmedNetworkVaults.length);
        console2.log("Operators:", operators_SymbioticCore.length);

        for (uint256 i; i < confirmedNetworkVaults.length; ++i) {
            for (uint256 j; j < operators_SymbioticCore.length; ++j) {
                if (
                    ISymbioticOptInService(symbioticCore.operatorVaultOptInService).isOptedIn(
                        operators_SymbioticCore[j].addr, confirmedNetworkVaults[i]
                    ) && _randomChoice_Symbiotic(SELECT_OPERATOR_CHANCE)
                ) {
                    _operatorOptInWeak_SymbioticCore(operators_SymbioticCore[j].addr, network.addr);
                    if (
                        _delegateToOperatorTry_SymbioticCore(
                            confirmedNetworkVaults[i], subnetwork, operators_SymbioticCore[j].addr
                        )
                    ) {
                        confirmedNetworkOperators[confirmedNetworkVaults[i]].push(operators_SymbioticCore[j].addr);
                    }
                }
            }

            console2.log("Confirmed Network Operators:", confirmedNetworkOperators[confirmedNetworkVaults[i]].length);
        }

        for (uint256 i; i < confirmedNetworkVaults.length; ++i) {
            console2.log("Confirmed Network Vault:", confirmedNetworkVaults[i]);
            console2.log("Confirmed Network Operators:", confirmedNetworkOperators[confirmedNetworkVaults[i]].length);
            for (uint256 j; j < confirmedNetworkOperators[confirmedNetworkVaults[i]].length; ++j) {
                console2.log("Operator:", confirmedNetworkOperators[confirmedNetworkVaults[i]][j]);
                console2.log(
                    "Stake:",
                    ISymbioticBaseDelegator(ISymbioticVault(confirmedNetworkVaults[i]).delegator()).stake(
                        subnetwork, confirmedNetworkOperators[confirmedNetworkVaults[i]][j]
                    )
                );
            }
        }
    }

    function test_NetworkAdvanced() public {
        address middleware = address(111);
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);
        uint96 identifier = 0;
        address collateral = tokens_SymbioticCore[0];
        bytes32 subnetwork = network.addr.subnetwork(identifier);

        console2.log("Network:", network.addr);
        console2.log("Identifier:", identifier);
        console2.log("Collateral:", collateral);

        for (uint256 i; i < vaults_SymbioticCore.length; ++i) {
            if (ISymbioticVault(vaults_SymbioticCore[i]).collateral() == collateral) {
                networkVaults.push(vaults_SymbioticCore[i]);
            }
        }

        uint256 N_VAULTS = 5;
        if (networkVaults.length < N_VAULTS) {
            for (uint256 i; i < N_VAULTS; ++i) {
                address vault =
                    _getVaultRandom_SymbioticCore(_vmWalletsToAddresses_Symbiotic(operators_SymbioticCore), collateral);
                vaults_SymbioticCore.push(vault);
                networkVaults.push(vault);
            }
        }

        console2.log("Network Vaults:", networkVaults.length);

        for (uint256 i; i < networkVaults.length; ++i) {
            _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, networkVaults[i], identifier);
            if (_delegateToNetworkTry_SymbioticCore(networkVaults[i], subnetwork)) {
                if (ISymbioticVault(networkVaults[i]).activeStake() == 0) {
                    for (uint256 j; j < stakers_SymbioticCore.length; ++j) {
                        if (_randomChoice_Symbiotic(SYMBIOTIC_CORE_DEPOSIT_INTO_VAULT_CHANCE)) {
                            _stakerDepositRandom_SymbioticCore(stakers_SymbioticCore[j].addr, networkVaults[i]);
                            if (_randomChoice_Symbiotic(SYMBIOTIC_CORE_WITHDRAW_FROM_VAULT_CHANCE)) {
                                _stakerWithdrawRandom_SymbioticCore(stakers_SymbioticCore[j].addr, networkVaults[i]);
                            }
                        }
                    }
                }
                confirmedNetworkVaults.push(networkVaults[i]);
            }
        }

        console2.log("Confirmed Network Vaults:", confirmedNetworkVaults.length);
        console2.log("Operators:", operators_SymbioticCore.length);

        for (uint256 i; i < confirmedNetworkVaults.length; ++i) {
            for (uint256 j; j < operators_SymbioticCore.length; ++j) {
                if (_randomChoice_Symbiotic(SELECT_OPERATOR_CHANCE)) {
                    _operatorOptInWeak_SymbioticCore(operators_SymbioticCore[j].addr, confirmedNetworkVaults[i]);
                    _operatorOptInWeak_SymbioticCore(operators_SymbioticCore[j].addr, network.addr);
                    if (
                        _delegateToOperatorTry_SymbioticCore(
                            confirmedNetworkVaults[i], subnetwork, operators_SymbioticCore[j].addr
                        )
                    ) {
                        confirmedNetworkOperators[confirmedNetworkVaults[i]].push(operators_SymbioticCore[j].addr);
                    }
                }
            }

            console2.log("Confirmed Network Operators:", confirmedNetworkOperators[confirmedNetworkVaults[i]].length);
        }

        for (uint256 i; i < confirmedNetworkVaults.length; ++i) {
            console2.log("Confirmed Network Vault:", confirmedNetworkVaults[i]);
            console2.log("Confirmed Network Operators:", confirmedNetworkOperators[confirmedNetworkVaults[i]].length);
            for (uint256 j; j < confirmedNetworkOperators[confirmedNetworkVaults[i]].length; ++j) {
                console2.log("Operator:", confirmedNetworkOperators[confirmedNetworkVaults[i]][j]);
                console2.log(
                    "Stake:",
                    ISymbioticBaseDelegator(ISymbioticVault(confirmedNetworkVaults[i]).delegator()).stake(
                        subnetwork, confirmedNetworkOperators[confirmedNetworkVaults[i]][j]
                    )
                );
            }
        }

        for (uint256 i; i < confirmedNetworkVaults.length; ++i) {
            for (uint256 j; j < networks_SymbioticCore.length; ++j) {
                for (uint256 k; k < SYMBIOTIC_CORE_SUBNETWORKS.length; ++k) {
                    bytes32 subnetwork = networks_SymbioticCore[j].addr.subnetwork(SYMBIOTIC_CORE_SUBNETWORKS[k]);
                    for (uint256 l; l < operators_SymbioticCore.length; ++l) {
                        if (
                            _networkPossibleUtilizing_SymbioticCore(
                                networks_SymbioticCore[j].addr,
                                SYMBIOTIC_CORE_SUBNETWORKS[k],
                                confirmedNetworkVaults[i],
                                operators_SymbioticCore[l].addr
                            )
                        ) {
                            neighborNetworks[confirmedNetworkVaults[i]].push(subnetwork);
                            break;
                        }
                    }
                }
            }
        }

        for (uint256 i; i < confirmedNetworkVaults.length; ++i) {
            console2.log("Confirmed Network Vault:", confirmedNetworkVaults[i]);
            console2.log("Neighbor Networks:", neighborNetworks[confirmedNetworkVaults[i]].length);
            for (uint256 j; j < neighborNetworks[confirmedNetworkVaults[i]].length; ++j) {
                console2.log("Neighbor Network:", vm.toString(neighborNetworks[confirmedNetworkVaults[i]][j]));
            }
        }
    }

    function test_Simple() public {
        address network = networks_SymbioticCore[0].addr;
        uint96 identifier = SYMBIOTIC_CORE_SUBNETWORKS[0];
        address collateral = tokens_SymbioticCore[0];
        bytes32 subnetwork = network.subnetwork(identifier);

        for (uint256 i; i < vaultsForSubnetwork[subnetwork].length; ++i) {
            address vault = vaultsForSubnetwork[subnetwork][i];
            console2.log("Vault:", vault);
        }

        for (uint256 i; i < vaultsForSubnetwork[subnetwork].length; ++i) {
            address vault = vaultsForSubnetwork[subnetwork][i];
            if (ISymbioticVault(vault).collateral() == collateral) {
                for (uint256 j; j < confirmedOperatorsForSubnetwork[subnetwork][vault].length; ++j) {
                    address operator = confirmedOperatorsForSubnetwork[subnetwork][vault][j];
                    console2.log("Vault/Operator:", vault, operator);
                }
            }
        }

        address vault = vaultsForSubnetwork[subnetwork][0];
        Vm.Wallet memory newOperator = _getOperatorWithOptIns_SymbioticCore(vault, network);
        _delegateTry_SymbioticCore(vault, subnetwork, newOperator.addr);

        console2.log(
            "Stake before new staker:",
            ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).stake(subnetwork, newOperator.addr)
        );
        console2.log("Total stake before new staker:", ISymbioticVault(vault).totalStake());

        Vm.Wallet memory newStaker = _getStakerWithStake_SymbioticCore(tokens_SymbioticCore, vault);

        console2.log(
            "Stake after new staker:",
            ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).stake(subnetwork, newOperator.addr)
        );
        console2.log("Total stake after new staker:", ISymbioticVault(vault).totalStake());
        console2.log("User stake:", ISymbioticVault(vault).slashableBalanceOf(newStaker.addr));
    }
}

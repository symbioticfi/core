// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {Vault} from "../../../src/contracts/vault/Vault.sol";
import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IOperatorSpecificDelegator} from "../../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {
    IOperatorNetworkSpecificDelegator
} from "../../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IBaseSlasher} from "../../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";
import {NetworkRestakeDelegator} from "../../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

contract DeployVaultBase is Script {
    struct VaultParams {
        IVault.InitParams baseParams;
        address[] whitelistedDepositors;
    }

    struct DelegatorParams {
        IBaseDelegator.BaseParams baseParams;
        address[] networkAllocationSettersOrNetwork;
        address[] operatorAllocationSettersOrOperator;
    }

    struct SlasherParams {
        IBaseSlasher.BaseParams baseParams;
        uint48 vetoDuration;
        uint48 resolverSetEpochsDelay;
    }

    struct DeployVaultParams {
        address owner;
        VaultParams vaultParams;
        uint64 delegatorIndex;
        DelegatorParams delegatorParams;
        bool withSlasher;
        uint64 slasherIndex;
        SlasherParams slasherParams;
    }

    bytes32 DEFAULT_ADMIN_ROLE = 0x00;

    function run(DeployVaultParams memory params) public returns (address, address, address) {
        vm.startBroadcast();
        (,, address deployer) = vm.readCallers();

        bytes memory delegatorParamsEncoded;
        IBaseDelegator.BaseParams memory baseParams = IBaseDelegator.BaseParams({
            defaultAdminRoleHolder: params.delegatorParams.baseParams.defaultAdminRoleHolder,
            hook: params.delegatorParams.baseParams.hook,
            hookSetRoleHolder: params.delegatorParams.baseParams.hookSetRoleHolder
        });
        if (params.delegatorIndex == 0) {
            delegatorParamsEncoded = abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: params.delegatorParams.networkAllocationSettersOrNetwork,
                    operatorNetworkSharesSetRoleHolders: params.delegatorParams.operatorAllocationSettersOrOperator
                })
            );
        } else if (params.delegatorIndex == 1) {
            delegatorParamsEncoded = abi.encode(
                IFullRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: params.delegatorParams.networkAllocationSettersOrNetwork,
                    operatorNetworkLimitSetRoleHolders: params.delegatorParams.operatorAllocationSettersOrOperator
                })
            );
        } else if (params.delegatorIndex == 2) {
            assert(params.delegatorParams.operatorAllocationSettersOrOperator.length == 1);
            delegatorParamsEncoded = abi.encode(
                IOperatorSpecificDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: params.delegatorParams.networkAllocationSettersOrNetwork,
                    operator: params.delegatorParams.operatorAllocationSettersOrOperator[0]
                })
            );
        } else if (params.delegatorIndex == 3) {
            assert(params.delegatorParams.networkAllocationSettersOrNetwork.length == 1);
            assert(params.delegatorParams.operatorAllocationSettersOrOperator.length == 1);
            delegatorParamsEncoded = abi.encode(
                IOperatorNetworkSpecificDelegator.InitParams({
                    baseParams: baseParams,
                    network: params.delegatorParams.networkAllocationSettersOrNetwork[0],
                    operator: params.delegatorParams.operatorAllocationSettersOrOperator[0]
                })
            );
        }

        bytes memory slasherParamsEncoded;
        if (params.slasherIndex == 0) {
            slasherParamsEncoded = abi.encode(
                ISlasher.InitParams({
                    baseParams: IBaseSlasher.BaseParams({isBurnerHook: params.slasherParams.baseParams.isBurnerHook})
                })
            );
        } else if (params.slasherIndex == 1) {
            slasherParamsEncoded = abi.encode(
                IVetoSlasher.InitParams({
                    baseParams: IBaseSlasher.BaseParams({isBurnerHook: params.slasherParams.baseParams.isBurnerHook}),
                    vetoDuration: params.slasherParams.vetoDuration,
                    resolverSetEpochsDelay: params.slasherParams.resolverSetEpochsDelay
                })
            );
        }

        (address vault_, address delegator_, address slasher_) = IVaultConfigurator(
                SymbioticCoreConstants.core().vaultConfigurator
            )
            .create(
                IVaultConfigurator.InitParams({
                    version: _getVaultVersion(),
                    owner: params.owner,
                    vaultParams: _getVaultParamsEncoded(params),
                    delegatorIndex: params.delegatorIndex,
                    delegatorParams: delegatorParamsEncoded,
                    withSlasher: params.withSlasher,
                    slasherIndex: params.slasherIndex,
                    slasherParams: slasherParamsEncoded
                })
            );

        if (params.vaultParams.whitelistedDepositors.length != 0) {
            for (uint256 i; i < params.vaultParams.whitelistedDepositors.length; ++i) {
                Vault(vault_).setDepositorWhitelistStatus(params.vaultParams.whitelistedDepositors[i], true);
            }

            if (deployer != params.vaultParams.baseParams.depositorWhitelistRoleHolder) {
                Vault(vault_)
                    .grantRole(
                        Vault(vault_).DEPOSITOR_WHITELIST_ROLE(),
                        params.vaultParams.baseParams.depositorWhitelistRoleHolder
                    );
                Vault(vault_).renounceRole(Vault(vault_).DEPOSITOR_WHITELIST_ROLE(), deployer);
            }

            if (deployer != params.vaultParams.baseParams.defaultAdminRoleHolder) {
                Vault(vault_).grantRole(DEFAULT_ADMIN_ROLE, params.vaultParams.baseParams.defaultAdminRoleHolder);
                Vault(vault_).renounceRole(DEFAULT_ADMIN_ROLE, deployer);
            }
        }

        Logs.log(
            string.concat(
                "Deployed vault",
                "\n    vault:",
                vm.toString(vault_),
                "\n    delegator:",
                vm.toString(delegator_),
                "\n    slasher:",
                vm.toString(slasher_)
            )
        );

        _validateOwnershipTransfer(vault_, delegator_, params);

        vm.stopBroadcast();
        return (vault_, delegator_, slasher_);
    }

    function _getVaultVersion() internal virtual returns (uint64) {
        return 1;
    }

    function _getVaultParamsEncoded(DeployVaultParams memory params) internal virtual returns (bytes memory) {
        (,, address deployer) = vm.readCallers();
        bool needWhitelistDepositors = params.vaultParams.whitelistedDepositors.length != 0;

        IVault.InitParams memory baseParams = params.vaultParams.baseParams;
        baseParams.defaultAdminRoleHolder =
            needWhitelistDepositors ? deployer : params.vaultParams.baseParams.defaultAdminRoleHolder;
        baseParams.depositorWhitelistRoleHolder =
            needWhitelistDepositors ? deployer : params.vaultParams.baseParams.depositorWhitelistRoleHolder;

        return abi.encode(baseParams);
    }

    function _validateOwnershipTransfer(address vault, address delegator, DeployVaultParams memory params) internal {
        (,, address deployer) = vm.readCallers();
        // Validate vault role transfers
        assert(Vault(vault).owner() == params.owner);
        if (params.vaultParams.baseParams.defaultAdminRoleHolder != address(0)) {
            assert(
                Vault(vault).hasRole(DEFAULT_ADMIN_ROLE, params.vaultParams.baseParams.defaultAdminRoleHolder) == true
            );
        }
        if (params.vaultParams.baseParams.depositLimitSetRoleHolder != address(0)) {
            assert(
                Vault(vault)
                    .hasRole(
                        Vault(vault).DEPOSIT_LIMIT_SET_ROLE(), params.vaultParams.baseParams.depositLimitSetRoleHolder
                    ) == true
            );
        }
        if (params.vaultParams.baseParams.isDepositLimitSetRoleHolder != address(0)) {
            assert(
                Vault(vault)
                    .hasRole(
                        Vault(vault).IS_DEPOSIT_LIMIT_SET_ROLE(),
                        params.vaultParams.baseParams.isDepositLimitSetRoleHolder
                    ) == true
            );
        }
        if (params.vaultParams.baseParams.depositWhitelistSetRoleHolder != address(0)) {
            assert(
                Vault(vault)
                    .hasRole(
                        Vault(vault).DEPOSIT_WHITELIST_SET_ROLE(),
                        params.vaultParams.baseParams.depositWhitelistSetRoleHolder
                    ) == true
            );
        }
        if (params.vaultParams.baseParams.depositorWhitelistRoleHolder != address(0)) {
            assert(
                Vault(vault)
                    .hasRole(
                        Vault(vault).DEPOSITOR_WHITELIST_ROLE(),
                        params.vaultParams.baseParams.depositorWhitelistRoleHolder
                    ) == true
            );
        }
        if (deployer != params.vaultParams.baseParams.defaultAdminRoleHolder) {
            assert(Vault(vault).hasRole(DEFAULT_ADMIN_ROLE, deployer) == false);
        }
        if (deployer != params.vaultParams.baseParams.depositLimitSetRoleHolder) {
            assert(Vault(vault).hasRole(Vault(vault).DEPOSIT_LIMIT_SET_ROLE(), deployer) == false);
        }
        if (deployer != params.vaultParams.baseParams.isDepositLimitSetRoleHolder) {
            assert(Vault(vault).hasRole(Vault(vault).IS_DEPOSIT_LIMIT_SET_ROLE(), deployer) == false);
        }
        if (deployer != params.vaultParams.baseParams.depositWhitelistSetRoleHolder) {
            assert(Vault(vault).hasRole(Vault(vault).DEPOSIT_WHITELIST_SET_ROLE(), deployer) == false);
        }
        if (deployer != params.vaultParams.baseParams.depositorWhitelistRoleHolder) {
            assert(Vault(vault).hasRole(Vault(vault).DEPOSITOR_WHITELIST_ROLE(), deployer) == false);
        }

        // Validate delegator role transfers based on delegator type
        if (params.delegatorIndex == 0) {
            if (params.delegatorParams.baseParams.defaultAdminRoleHolder != address(0)) {
                assert(
                    NetworkRestakeDelegator(delegator)
                        .hasRole(DEFAULT_ADMIN_ROLE, params.delegatorParams.baseParams.defaultAdminRoleHolder) == true
                );
            }
            for (uint256 i; i < params.delegatorParams.networkAllocationSettersOrNetwork.length; ++i) {
                assert(
                    NetworkRestakeDelegator(delegator)
                        .hasRole(
                            NetworkRestakeDelegator(delegator).NETWORK_LIMIT_SET_ROLE(),
                            params.delegatorParams.networkAllocationSettersOrNetwork[i]
                        ) == true
                );
            }
            for (uint256 i; i < params.delegatorParams.operatorAllocationSettersOrOperator.length; ++i) {
                assert(
                    NetworkRestakeDelegator(delegator)
                        .hasRole(
                            NetworkRestakeDelegator(delegator).OPERATOR_NETWORK_SHARES_SET_ROLE(),
                            params.delegatorParams.operatorAllocationSettersOrOperator[i]
                        ) == true
                );
            }
            if (params.delegatorParams.baseParams.hookSetRoleHolder != address(0)) {
                assert(
                    NetworkRestakeDelegator(delegator)
                        .hasRole(
                            NetworkRestakeDelegator(delegator).HOOK_SET_ROLE(),
                            params.delegatorParams.baseParams.hookSetRoleHolder
                        ) == true
                );
            }
        } else if (params.delegatorIndex == 1) {
            if (params.delegatorParams.baseParams.defaultAdminRoleHolder != address(0)) {
                assert(
                    FullRestakeDelegator(delegator)
                        .hasRole(DEFAULT_ADMIN_ROLE, params.delegatorParams.baseParams.defaultAdminRoleHolder) == true
                );
            }
            for (uint256 i; i < params.delegatorParams.networkAllocationSettersOrNetwork.length; ++i) {
                assert(
                    FullRestakeDelegator(delegator)
                        .hasRole(
                            FullRestakeDelegator(delegator).NETWORK_LIMIT_SET_ROLE(),
                            params.delegatorParams.networkAllocationSettersOrNetwork[i]
                        ) == true
                );
            }
            for (uint256 i; i < params.delegatorParams.operatorAllocationSettersOrOperator.length; ++i) {
                assert(
                    FullRestakeDelegator(delegator)
                        .hasRole(
                            FullRestakeDelegator(delegator).OPERATOR_NETWORK_LIMIT_SET_ROLE(),
                            params.delegatorParams.operatorAllocationSettersOrOperator[i]
                        ) == true
                );
            }
            if (params.delegatorParams.baseParams.hookSetRoleHolder != address(0)) {
                assert(
                    FullRestakeDelegator(delegator)
                        .hasRole(
                            FullRestakeDelegator(delegator).HOOK_SET_ROLE(),
                            params.delegatorParams.baseParams.hookSetRoleHolder
                        ) == true
                );
            }
        } else if (params.delegatorIndex == 2) {
            if (params.delegatorParams.baseParams.defaultAdminRoleHolder != address(0)) {
                assert(
                    OperatorSpecificDelegator(delegator)
                        .hasRole(DEFAULT_ADMIN_ROLE, params.delegatorParams.baseParams.defaultAdminRoleHolder) == true
                );
            }
            if (params.delegatorParams.baseParams.hookSetRoleHolder != address(0)) {
                assert(
                    OperatorSpecificDelegator(delegator)
                        .hasRole(
                            OperatorSpecificDelegator(delegator).HOOK_SET_ROLE(),
                            params.delegatorParams.baseParams.hookSetRoleHolder
                        ) == true
                );
            }
            assert(
                OperatorSpecificDelegator(delegator).operator()
                    == params.delegatorParams.operatorAllocationSettersOrOperator[0]
            );
        } else if (params.delegatorIndex == 3) {
            if (params.delegatorParams.baseParams.defaultAdminRoleHolder != address(0)) {
                assert(
                    OperatorNetworkSpecificDelegator(delegator)
                        .hasRole(DEFAULT_ADMIN_ROLE, params.delegatorParams.baseParams.defaultAdminRoleHolder) == true
                );
            }
            if (params.delegatorParams.baseParams.hookSetRoleHolder != address(0)) {
                assert(
                    OperatorNetworkSpecificDelegator(delegator)
                        .hasRole(
                            OperatorNetworkSpecificDelegator(delegator).HOOK_SET_ROLE(),
                            params.delegatorParams.baseParams.hookSetRoleHolder
                        ) == true
                );
            }
            assert(
                OperatorNetworkSpecificDelegator(delegator).network()
                    == params.delegatorParams.networkAllocationSettersOrNetwork[0]
            );
            assert(
                OperatorNetworkSpecificDelegator(delegator).operator()
                    == params.delegatorParams.operatorAllocationSettersOrOperator[0]
            );
        }
    }
}

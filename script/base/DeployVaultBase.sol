// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {Vault} from "../../src/contracts/vault/Vault.sol";

import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IOperatorSpecificDelegator} from "../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IOperatorNetworkSpecificDelegator} from "../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";

import {Logs} from "./Logs.sol";
import {SymbioticCoreConstants} from "../../test/integration/SymbioticCoreConstants.sol";

contract DeployVaultBase is Script, Logs {
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

    DeployVaultParams public params;

    constructor(
        DeployVaultParams memory params_
    ) {
        params = params_;
    }

    function run() public returns (address, address, address) {
        vm.startBroadcast();
        (,, address deployer) = vm.readCallers();

        bool needWhitelistDepositors = params.vaultParams.whitelistedDepositors.length != 0;

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

        bytes memory vaultParamsEncoded = _buildEncodedParams();

        (address vault_, address delegator_, address slasher_) = IVaultConfigurator(
            SymbioticCoreConstants.core().vaultConfigurator
        ).create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: params.owner,
                vaultParams: vaultParamsEncoded,
                delegatorIndex: params.delegatorIndex,
                delegatorParams: delegatorParamsEncoded,
                withSlasher: params.withSlasher,
                slasherIndex: params.slasherIndex,
                slasherParams: slasherParamsEncoded
            })
        );

        if (needWhitelistDepositors) {
            for (uint256 i; i < params.vaultParams.whitelistedDepositors.length; ++i) {
                Vault(vault_).setDepositorWhitelistStatus(params.vaultParams.whitelistedDepositors[i], true);
            }

            if (deployer != params.vaultParams.baseParams.depositorWhitelistRoleHolder) {
                Vault(vault_).grantRole(
                    Vault(vault_).DEPOSITOR_WHITELIST_ROLE(), params.vaultParams.baseParams.depositorWhitelistRoleHolder
                );
                Vault(vault_).renounceRole(Vault(vault_).DEPOSITOR_WHITELIST_ROLE(), deployer);
            }

            if (deployer != params.vaultParams.baseParams.defaultAdminRoleHolder) {
                Vault(vault_).grantRole(
                    Vault(vault_).DEFAULT_ADMIN_ROLE(), params.vaultParams.baseParams.defaultAdminRoleHolder
                );
                Vault(vault_).renounceRole(Vault(vault_).DEFAULT_ADMIN_ROLE(), deployer);
            }
        }

        log(
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

        vm.stopBroadcast();
        return (vault_, delegator_, slasher_);
    }

    function _buildEncodedParams() internal virtual returns (bytes memory vaultParamsEncoded) {
        (,, address deployer) = vm.readCallers();
        bool needWhitelistDepositors = params.vaultParams.whitelistedDepositors.length != 0;

        vaultParamsEncoded = abi.encode(
            IVault.InitParams({
                collateral: params.vaultParams.baseParams.collateral,
                burner: params.vaultParams.baseParams.burner,
                epochDuration: params.vaultParams.baseParams.epochDuration,
                depositWhitelist: params.vaultParams.baseParams.depositWhitelist,
                isDepositLimit: params.vaultParams.baseParams.isDepositLimit,
                depositLimit: params.vaultParams.baseParams.depositLimit,
                defaultAdminRoleHolder: needWhitelistDepositors
                    ? deployer
                    : params.vaultParams.baseParams.defaultAdminRoleHolder,
                depositWhitelistSetRoleHolder: params.vaultParams.baseParams.depositWhitelistSetRoleHolder,
                depositorWhitelistRoleHolder: needWhitelistDepositors
                    ? deployer
                    : params.vaultParams.baseParams.depositorWhitelistRoleHolder,
                isDepositLimitSetRoleHolder: params.vaultParams.baseParams.isDepositLimitSetRoleHolder,
                depositLimitSetRoleHolder: params.vaultParams.baseParams.depositLimitSetRoleHolder
            })
        );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {Vault} from "../../../src/contracts/vault/Vault.sol";

import {IMigratablesFactory} from "../../../src/interfaces/common/IMigratablesFactory.sol";
import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IOperatorSpecificDelegator} from "../../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IOperatorNetworkSpecificDelegator} from
    "../../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IBaseSlasher} from "../../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";

contract VaultBase is Script {
    struct VaultParams {
        address vaultConfigurator;
        address owner;
        address collateral;
        address burner;
        uint48 epochDuration;
        address[] whitelistedDepositors;
        uint256 depositLimit;
        uint64 delegatorIndex;
        address hook;
        address network;
        bool withSlasher;
        uint64 slasherIndex;
        uint48 vetoDuration;
    }

    VaultParams public vaultParams;

    constructor(
        VaultParams memory params
    ) {
        vaultParams = params;
    }

    function run() public {
        vm.startBroadcast();
        (,, address deployer) = vm.readCallers();

        bool depositWhitelist = vaultParams.whitelistedDepositors.length != 0;

        bytes memory initParamsEncoded = abi.encode(
            IVault.InitParams({
                collateral: vaultParams.collateral,
                burner: vaultParams.burner,
                epochDuration: vaultParams.epochDuration,
                depositWhitelist: depositWhitelist,
                isDepositLimit: vaultParams.depositLimit != 0,
                depositLimit: vaultParams.depositLimit,
                defaultAdminRoleHolder: depositWhitelist ? deployer : vaultParams.owner,
                depositWhitelistSetRoleHolder: vaultParams.owner,
                depositorWhitelistRoleHolder: vaultParams.owner,
                isDepositLimitSetRoleHolder: vaultParams.owner,
                depositLimitSetRoleHolder: vaultParams.owner
            })
        );

        uint256 roleHolders = 1;
        if (vaultParams.hook != address(0) && vaultParams.hook != vaultParams.owner) {
            roleHolders = 2;
        }
        address[] memory networkLimitSetRoleHolders = new address[](roleHolders);
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](roleHolders);
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](roleHolders);
        networkLimitSetRoleHolders[0] = vaultParams.owner;
        operatorNetworkLimitSetRoleHolders[0] = vaultParams.owner;
        operatorNetworkSharesSetRoleHolders[0] = vaultParams.owner;
        if (roleHolders > 1) {
            networkLimitSetRoleHolders[1] = vaultParams.hook;
            operatorNetworkLimitSetRoleHolders[1] = vaultParams.hook;
            operatorNetworkSharesSetRoleHolders[1] = vaultParams.hook;
        }

        bytes memory delegatorParams;
        IBaseDelegator.BaseParams memory baseParams = IBaseDelegator.BaseParams({
            defaultAdminRoleHolder: vaultParams.owner,
            hook: vaultParams.hook,
            hookSetRoleHolder: vaultParams.owner
        });
        if (vaultParams.delegatorIndex == 0) {
            delegatorParams = abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                })
            );
        } else if (vaultParams.delegatorIndex == 1) {
            delegatorParams = abi.encode(
                IFullRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                })
            );
        } else if (vaultParams.delegatorIndex == 2) {
            delegatorParams = abi.encode(
                IOperatorSpecificDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operator: vaultParams.owner
                })
            );
        } else if (vaultParams.delegatorIndex == 3) {
            delegatorParams = abi.encode(
                IOperatorNetworkSpecificDelegator.InitParams({
                    baseParams: baseParams,
                    network: vaultParams.network,
                    operator: vaultParams.owner
                })
            );
        }

        bytes memory slasherParams;
        if (vaultParams.slasherIndex == 0) {
            slasherParams = abi.encode(
                ISlasher.InitParams({
                    baseParams: IBaseSlasher.BaseParams({isBurnerHook: vaultParams.burner != address(0)})
                })
            );
        } else if (vaultParams.slasherIndex == 1) {
            slasherParams = abi.encode(
                IVetoSlasher.InitParams({
                    baseParams: IBaseSlasher.BaseParams({isBurnerHook: vaultParams.burner != address(0)}),
                    vetoDuration: vaultParams.vetoDuration,
                    resolverSetEpochsDelay: 3
                })
            );
        }

        (address vault_, address delegator_, address slasher_) = IVaultConfigurator(vaultParams.vaultConfigurator)
            .create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: vaultParams.owner,
                vaultParams: initParamsEncoded,
                delegatorIndex: vaultParams.delegatorIndex,
                delegatorParams: delegatorParams,
                withSlasher: vaultParams.withSlasher,
                slasherIndex: vaultParams.slasherIndex,
                slasherParams: slasherParams
            })
        );

        if (depositWhitelist) {
            Vault(vault_).grantRole(Vault(vault_).DEFAULT_ADMIN_ROLE(), vaultParams.owner);
            Vault(vault_).grantRole(Vault(vault_).DEPOSITOR_WHITELIST_ROLE(), deployer);

            for (uint256 i; i < vaultParams.whitelistedDepositors.length; ++i) {
                Vault(vault_).setDepositorWhitelistStatus(vaultParams.whitelistedDepositors[i], true);
            }

            Vault(vault_).renounceRole(Vault(vault_).DEPOSITOR_WHITELIST_ROLE(), deployer);
            Vault(vault_).renounceRole(Vault(vault_).DEFAULT_ADMIN_ROLE(), deployer);
        }

        console2.log("Vault: ", vault_);
        console2.log("Delegator: ", delegator_);
        console2.log("Slasher: ", slasher_);

        vm.stopBroadcast();
    }
}

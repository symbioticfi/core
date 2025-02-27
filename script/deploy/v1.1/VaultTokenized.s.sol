// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {console2} from "forge-std/Script.sol";

import {SymbioticCoreInit} from "../../integration/SymbioticCoreInit.sol";

import {IVault} from "../../../src/interfaces/vault/v1.1/IVault.sol";
import {IVaultTokenized} from "../../../src/interfaces/vault/v1.1/IVaultTokenized.sol";
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

contract VaultTokenizedScript is SymbioticCoreInit {
    function run(
        address owner,
        address collateral,
        address burner,
        uint48 epochDuration,
        address[] calldata depositorsWhitelisted,
        uint256 depositLimit,
        address flashFeeReceiver,
        uint256 flashFeeRate,
        string calldata name,
        string calldata symbol,
        uint64 delegatorIndex,
        address hook,
        address network,
        bool withSlasher,
        uint64 slasherIndex,
        uint48 vetoDuration
    ) public {
        SymbioticCoreInit.run(0);

        vm.startBroadcast();

        bytes memory vaultParams = abi.encode(
            IVaultTokenized.InitParamsTokenized({
                baseParams: abi.encode(
                    IVault.InitParams({
                        collateral: collateral,
                        burner: burner,
                        epochDuration: epochDuration,
                        depositWhitelist: depositorsWhitelisted.length != 0,
                        isDepositLimit: depositLimit != 0,
                        depositLimit: depositLimit,
                        epochDurationSetEpochsDelay: 3,
                        flashLoanEnabled: flashFeeReceiver != address(0),
                        flashFeeRate: flashFeeRate,
                        flashFeeReceiver: flashFeeReceiver,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: owner,
                        depositorWhitelistRoleHolder: owner,
                        depositorsWhitelisted: depositorsWhitelisted,
                        isDepositLimitSetRoleHolder: owner,
                        depositLimitSetRoleHolder: owner,
                        epochDurationSetRoleHolder: owner,
                        flashLoanEnabledSetRoleHolder: owner,
                        flashFeeRateSetRoleHolder: owner,
                        flashFeeReceiverSetRoleHolder: owner
                    })
                ),
                name: name,
                symbol: symbol
            })
        );

        uint256 roleHolders = 1;
        if (hook != address(0) && hook != owner) {
            roleHolders = 2;
        }
        address[] memory networkLimitSetRoleHolders = new address[](roleHolders);
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](roleHolders);
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](roleHolders);
        networkLimitSetRoleHolders[0] = owner;
        operatorNetworkLimitSetRoleHolders[0] = owner;
        operatorNetworkSharesSetRoleHolders[0] = owner;
        if (roleHolders > 1) {
            networkLimitSetRoleHolders[1] = hook;
            operatorNetworkLimitSetRoleHolders[1] = hook;
            operatorNetworkSharesSetRoleHolders[1] = hook;
        }

        bytes memory delegatorParams;
        if (delegatorIndex == 0) {
            delegatorParams = abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: IBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                })
            );
        } else if (delegatorIndex == 1) {
            delegatorParams = abi.encode(
                IFullRestakeDelegator.InitParams({
                    baseParams: IBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                })
            );
        } else if (delegatorIndex == 2) {
            delegatorParams = abi.encode(
                IOperatorSpecificDelegator.InitParams({
                    baseParams: IBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operator: owner
                })
            );
        } else if (delegatorIndex == 3) {
            delegatorParams = abi.encode(
                IOperatorNetworkSpecificDelegator.InitParams({
                    baseParams: IBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    network: network,
                    operator: owner
                })
            );
        }

        bytes memory slasherParams;
        if (slasherIndex == 0) {
            slasherParams = abi.encode(
                ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: burner != address(0)})})
            );
        } else if (slasherIndex == 1) {
            slasherParams = abi.encode(
                IVetoSlasher.InitParams({
                    baseParams: IBaseSlasher.BaseParams({isBurnerHook: burner != address(0)}),
                    vetoDuration: vetoDuration,
                    resolverSetEpochsDelay: 3
                })
            );
        }

        (address vault_, address delegator_, address slasher_) = symbioticCore.vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 4,
                owner: owner,
                vaultParams: vaultParams,
                delegatorIndex: delegatorIndex,
                delegatorParams: delegatorParams,
                withSlasher: withSlasher,
                slasherIndex: slasherIndex,
                slasherParams: slasherParams
            })
        );

        console2.log("Vault: ", vault_);
        console2.log("Delegator: ", delegator_);
        console2.log("Slasher: ", slasher_);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {IMigratablesFactory} from "src/interfaces/common/IMigratablesFactory.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "src/interfaces/IVaultConfigurator.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";
import {IFullRestakeDelegator} from "src/interfaces/delegator/IFullRestakeDelegator.sol";

contract VaultScript is Script {
    function run(
        address vaultConfigurator,
        address owner,
        address collateral,
        uint48 epochDuration,
        bool depositWhitelist
    ) public {
        vm.startBroadcast();

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = owner;
        (address vault_, address delegator_,) = IVaultConfigurator(vaultConfigurator).create(
            IVaultConfigurator.InitParams({
                version: IMigratablesFactory(IVaultConfigurator(vaultConfigurator).VAULT_FACTORY()).lastVersion(),
                owner: owner,
                vaultParams: IVault.InitParams({
                    collateral: address(collateral),
                    delegator: address(0),
                    slasher: address(0),
                    burner: address(0xdEaD),
                    epochDuration: epochDuration,
                    depositWhitelist: depositWhitelist,
                    defaultAdminRoleHolder: owner,
                    depositorWhitelistRoleHolder: owner
                }),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: owner,
                            hook: address(0),
                            hookSetRoleHolder: owner
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        console2.log("Vault: ", vault_);
        console2.log("Delegator: ", delegator_);

        vm.stopBroadcast();
    }
}

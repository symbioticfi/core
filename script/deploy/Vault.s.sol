// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {IMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";

contract VaultScript is Script {
    function run(
        address vaultConfigurator,
        address owner,
        address collateral,
        uint48 epochDuration,
        bool depositWhitelist,
        uint256 depositLimit,
        uint64 delegatorIndex,
        bool withSlasher,
        uint64 slasherIndex,
        uint48 vetoDuration
    ) public {
        vm.startBroadcast();

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = owner;
        (address vault_, address delegator_, address slasher_) = IVaultConfigurator(vaultConfigurator).create(
            IVaultConfigurator.InitParams({
                version: IMigratablesFactory(IVaultConfigurator(vaultConfigurator).VAULT_FACTORY()).lastVersion(),
                owner: owner,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: depositWhitelist,
                        isDepositLimit: depositLimit != 0,
                        depositLimit: depositLimit,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: owner,
                        depositorWhitelistRoleHolder: owner,
                        isDepositLimitSetRoleHolder: owner,
                        depositLimitSetRoleHolder: owner
                    })
                ),
                delegatorIndex: delegatorIndex,
                delegatorParams: delegatorIndex == 0
                    ? abi.encode(
                        INetworkRestakeDelegator.InitParams({
                            baseParams: IBaseDelegator.BaseParams({
                                defaultAdminRoleHolder: owner,
                                hook: address(0),
                                hookSetRoleHolder: owner
                            }),
                            networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                            operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                        })
                    )
                    : abi.encode(
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
                withSlasher: withSlasher,
                slasherIndex: slasherIndex,
                slasherParams: slasherIndex == 0
                    ? new bytes(0)
                    : abi.encode(IVetoSlasher.InitParams({vetoDuration: vetoDuration, resolverSetEpochsDelay: 3}))
            })
        );

        console2.log("Vault: ", vault_);
        console2.log("Delegator: ", delegator_);
        console2.log("Slasher: ", slasher_);

        vm.stopBroadcast();
    }
}

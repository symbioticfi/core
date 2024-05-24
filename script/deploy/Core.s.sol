// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {MigratablesFactory} from "src/contracts/base/MigratablesFactory.sol";
import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {MetadataPlugin} from "src/contracts/MetadataPlugin.sol";
import {MiddlewarePlugin} from "src/contracts/MiddlewarePlugin.sol";
import {NetworkOptInPlugin} from "src/contracts/NetworkOptInPlugin.sol";
import {OperatorOptInPlugin} from "src/contracts/OperatorOptInPlugin.sol";
import {Vault} from "src/contracts/vault/v1/Vault.sol";

contract CoreScript is Script {
    function run(address owner) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        NonMigratablesRegistry operatorRegistry = new NonMigratablesRegistry();
        MigratablesFactory vaultRegistry = new MigratablesFactory(owner);
        NonMigratablesRegistry networkRegistry = new NonMigratablesRegistry();
        MetadataPlugin operatorMetadataPlugin = new MetadataPlugin(address(operatorRegistry));
        MetadataPlugin networkMetadataPlugin = new MetadataPlugin(address(networkRegistry));
        MiddlewarePlugin networkMiddlewarePlugin = new MiddlewarePlugin(address(networkRegistry));
        NetworkOptInPlugin networkVaultOptInPlugin =
            new NetworkOptInPlugin(address(networkRegistry), address(vaultRegistry));
        OperatorOptInPlugin operatorVaultOptInPlugin =
            new OperatorOptInPlugin(address(operatorRegistry), address(vaultRegistry));
        OperatorOptInPlugin operatorNetworkOptInPlugin =
            new OperatorOptInPlugin(address(operatorRegistry), address(networkRegistry));

        vaultRegistry.whitelist(
            address(
                new Vault(
                    address(networkRegistry),
                    address(operatorRegistry),
                    address(networkMiddlewarePlugin),
                    address(networkVaultOptInPlugin),
                    address(operatorVaultOptInPlugin),
                    address(operatorNetworkOptInPlugin)
                )
            )
        );
        vaultRegistry.transferOwnership(owner);

        vm.stopBroadcast();
    }
}

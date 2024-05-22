// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {MigratablesRegistry} from "src/contracts/base/MigratablesRegistry.sol";
import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {MetadataPlugin} from "src/contracts/plugins/MetadataPlugin.sol";
import {MiddlewarePlugin} from "src/contracts/plugins/MiddlewarePlugin.sol";
import {NetworkOptInPlugin} from "src/contracts/plugins/NetworkOptInPlugin.sol";
import {OperatorOptInPlugin} from "src/contracts/plugins/OperatorOptInPlugin.sol";

import {Vault} from "src/contracts/Vault.sol";

contract CoreScript is Script {
    function run(address owner) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        NonMigratablesRegistry operatorRegistry = new NonMigratablesRegistry();
        MigratablesRegistry vaultRegistry = new MigratablesRegistry(owner);
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

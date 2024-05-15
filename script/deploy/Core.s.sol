// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {MigratablesRegistry} from "src/contracts/MigratablesRegistry.sol";
import {NonMigratablesRegistry} from "src/contracts/NonMigratablesRegistry.sol";
import {MetadataExtension} from "src/contracts/extensions/MetadataExtension.sol";
import {MiddlewareExtension} from "src/contracts/extensions/MiddlewareExtension.sol";
import {NetworkOptInExtension} from "src/contracts/extensions/NetworkOptInExtension.sol";

import {Vault} from "src/contracts/Vault.sol";

contract CoreScript is Script {
    function run(address owner) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        NonMigratablesRegistry operatorRegistry = new NonMigratablesRegistry();
        MigratablesRegistry vaultRegistry = new MigratablesRegistry(owner);
        NonMigratablesRegistry networkRegistry = new NonMigratablesRegistry();
        MetadataExtension operatorMetadataExtension = new MetadataExtension(address(operatorRegistry));
        MetadataExtension networkMetadataExtension = new MetadataExtension(address(networkRegistry));
        MiddlewareExtension networkMiddlewareExtension = new MiddlewareExtension(address(networkRegistry));
        NetworkOptInExtension networkOptInExtension =
            new NetworkOptInExtension(address(operatorRegistry), address(networkRegistry));

        address vault = address(
            new Vault(
                address(networkRegistry),
                address(operatorRegistry),
                address(networkMiddlewareExtension),
                address(networkOptInExtension)
            )
        );
        vaultRegistry.whitelist(vault);
        vaultRegistry.transferOwnership(owner);

        vm.stopBroadcast();
    }
}

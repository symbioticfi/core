// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {MigratablesFactory} from "src/contracts/base/MigratablesFactory.sol";
import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {MetadataService} from "src/contracts/MetadataService.sol";
import {MiddlewareService} from "src/contracts/MiddlewareService.sol";
import {NetworkOptInService} from "src/contracts/NetworkOptInService.sol";
import {OperatorOptInService} from "src/contracts/OperatorOptInService.sol";
import {Vault} from "src/contracts/vault/v1/Vault.sol";

contract CoreScript is Script {
    function run(address owner) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        NonMigratablesRegistry operatorRegistry = new NonMigratablesRegistry();
        MigratablesFactory vaultRegistry = new MigratablesFactory(owner);
        NonMigratablesRegistry networkRegistry = new NonMigratablesRegistry();
        MetadataService operatorMetadataService = new MetadataService(address(operatorRegistry));
        MetadataService networkMetadataService = new MetadataService(address(networkRegistry));
        MiddlewareService networkMiddlewareService = new MiddlewareService(address(networkRegistry));
        NetworkOptInService networkVaultOptInService =
            new NetworkOptInService(address(networkRegistry), address(vaultRegistry));
        OperatorOptInService operatorVaultOptInService =
            new OperatorOptInService(address(operatorRegistry), address(vaultRegistry));
        OperatorOptInService operatorNetworkOptInService =
            new OperatorOptInService(address(operatorRegistry), address(networkRegistry));

        vaultRegistry.whitelist(
            address(
                new Vault(
                    address(networkRegistry),
                    address(operatorRegistry),
                    address(networkMiddlewareService),
                    address(networkVaultOptInService),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService)
                )
            )
        );
        vaultRegistry.transferOwnership(owner);

        vm.stopBroadcast();
    }
}

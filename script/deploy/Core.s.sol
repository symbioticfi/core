// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {MetadataService} from "src/contracts/MetadataService.sol";
import {MiddlewareService} from "src/contracts/MiddlewareService.sol";
import {NetworkOptInService} from "src/contracts/NetworkOptInService.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorOptInService} from "src/contracts/OperatorOptInService.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {Vault} from "src/contracts/vault/v1/Vault.sol";

contract CoreScript is Script {
    function run(address owner) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        VaultFactory vaultFactory = new VaultFactory(owner);
        NetworkRegistry networkRegistry = new NetworkRegistry();
        OperatorRegistry operatorRegistry = new OperatorRegistry();
        MetadataService operatorMetadataService = new MetadataService(address(operatorRegistry));
        MetadataService networkMetadataService = new MetadataService(address(networkRegistry));
        MiddlewareService networkMiddlewareService = new MiddlewareService(address(networkRegistry));
        NetworkOptInService networkVaultOptInService =
            new NetworkOptInService(address(networkRegistry), address(vaultFactory));
        OperatorOptInService operatorVaultOptInService =
            new OperatorOptInService(address(operatorRegistry), address(vaultFactory));
        OperatorOptInService operatorNetworkOptInService =
            new OperatorOptInService(address(operatorRegistry), address(networkRegistry));

        vaultFactory.whitelist(
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
        vaultFactory.transferOwnership(owner);

        vm.stopBroadcast();
    }
}

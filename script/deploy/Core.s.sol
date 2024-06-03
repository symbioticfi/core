// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {MetadataService} from "src/contracts/MetadataService.sol";
import {NetworkMiddlewareService} from "src/contracts/NetworkMiddlewareService.sol";
import {NetworkOptInService} from "src/contracts/NetworkOptInService.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorOptInService} from "src/contracts/OperatorOptInService.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {Vault} from "src/contracts/vault/v1/Vault.sol";

contract CoreScript is Script {
    function run(address owner) public {
        vm.startBroadcast();
        (,, address deployer) = vm.readCallers();

        VaultFactory vaultFactory = new VaultFactory(deployer);
        NetworkRegistry networkRegistry = new NetworkRegistry();
        OperatorRegistry operatorRegistry = new OperatorRegistry();
        MetadataService operatorMetadataService = new MetadataService(address(operatorRegistry));
        MetadataService networkMetadataService = new MetadataService(address(networkRegistry));
        NetworkMiddlewareService networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        NetworkOptInService networkVaultOptInService =
            new NetworkOptInService(address(networkRegistry), address(vaultFactory));
        OperatorOptInService operatorVaultOptInService =
            new OperatorOptInService(address(operatorRegistry), address(vaultFactory));
        OperatorOptInService operatorNetworkOptInService =
            new OperatorOptInService(address(operatorRegistry), address(networkRegistry));

        vaultFactory.whitelist(
            address(
                new Vault(
                    address(vaultFactory),
                    address(networkRegistry),
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

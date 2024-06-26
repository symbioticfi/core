// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.25;

// import "forge-std/Script.sol";

// import {MetadataService} from "src/contracts/service/MetadataService.sol";
// import {NetworkMiddlewareService} from "src/contracts/service/NetworkMiddlewareService.sol";
// import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
// import {OptInService} from "src/contracts/service/OptInService.sol";
// import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
// import {VaultFactory} from "src/contracts/VaultFactory.sol";
// import {Vault} from "src/contracts/vault/Vault.sol";

// contract CoreScript is Script {
//     function run(address owner) public {
//         vm.startBroadcast();
//         (,, address deployer) = vm.readCallers();

//         VaultFactory vaultFactory = new VaultFactory(deployer);
//         NetworkRegistry networkRegistry = new NetworkRegistry();
//         OperatorRegistry operatorRegistry = new OperatorRegistry();
//         MetadataService operatorMetadataService = new MetadataService(address(operatorRegistry));
//         MetadataService networkMetadataService = new MetadataService(address(networkRegistry));
//         NetworkMiddlewareService networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
//         OptInService networkVaultOptInService =
//             new OptInService(address(networkRegistry), address(vaultFactory));
//         OptInService operatorVaultOptInService =
//             new OptInService(address(operatorRegistry), address(vaultFactory));
//         OptInService operatorNetworkOptInService =
//             new OptInService(address(operatorRegistry), address(networkRegistry));

//         vaultFactory.whitelist(
//             address(
//                 new Vault(
//                     address(vaultFactory),
//                     address(networkRegistry),
//                     address(networkMiddlewareService),
//                     address(networkVaultOptInService),
//                     address(operatorVaultOptInService),
//                     address(operatorNetworkOptInService)
//                 )
//             )
//         );
//         vaultFactory.transferOwnership(owner);

//         vm.stopBroadcast();
//     }
// }

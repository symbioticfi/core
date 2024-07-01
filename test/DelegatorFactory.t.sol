// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.25;

// import {Test, console2} from "forge-std/Test.sol";

// import {VaultFactory} from "src/contracts/VaultFactory.sol";
// import {DelegatorFactory} from "src/contracts/DelegatorFactory.sol";
// import {SlasherFactory} from "src/contracts/SlasherFactory.sol";
// import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
// import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
// import {MetadataService} from "src/contracts/service/MetadataService.sol";
// import {NetworkMiddlewareService} from "src/contracts/service/NetworkMiddlewareService.sol";
// import {OptInService} from "src/contracts/service/OptInService.sol";

// import {IEntity} from "src/interfaces/common/IEntity.sol";

// import {FullRestakeDelegator} from "src/contracts/delegator/FullRestakeDelegator.sol";
// import {NetworkRestakeDelegator} from "src/contracts/delegator/NetworkRestakeDelegator.sol";

// contract DelegatorFactoryTest is Test {
//     address owner;
//     address alice;
//     uint256 alicePrivateKey;
//     address bob;
//     uint256 bobPrivateKey;

//     VaultFactory vaultFactory;
//     DelegatorFactory delegatorFactory;
//     SlasherFactory slasherFactory;
//     NetworkRegistry networkRegistry;
//     OperatorRegistry operatorRegistry;
//     MetadataService operatorMetadataService;
//     MetadataService networkMetadataService;
//     NetworkMiddlewareService networkMiddlewareService;
//     OptInService networkVaultOptInService;
//     OptInService operatorVaultOptInService;
//     OptInService operatorNetworkOptInService;

//     function setUp() public {
//         owner = address(this);
//         (alice, alicePrivateKey) = makeAddrAndKey("alice");
//         (bob, bobPrivateKey) = makeAddrAndKey("bob");

//         vaultFactory = new VaultFactory(owner);
//         delegatorFactory = new DelegatorFactory(owner);
//         slasherFactory = new SlasherFactory(owner);
//         networkRegistry = new NetworkRegistry();
//         operatorRegistry = new OperatorRegistry();
//         operatorMetadataService = new MetadataService(address(operatorRegistry));
//         networkMetadataService = new MetadataService(address(networkRegistry));
//         networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
//         networkVaultOptInService = new OptInService(address(networkRegistry), address(vaultFactory));
//         operatorVaultOptInService = new OptInService(address(operatorRegistry), address(vaultFactory));
//         operatorNetworkOptInService = new OptInService(address(operatorRegistry), address(networkRegistry));
//     }

//     function test_Create() public {
//         address networkRestakeDelegatorImpl = address(
//             new NetworkRestakeDelegator(
//                 address(networkRegistry),
//                 address(vaultFactory),
//                 address(operatorVaultOptInService),
//                 address(operatorNetworkOptInService),
//                 address(delegatorFactory)
//             )
//         );
//         delegatorFactory.whitelist(networkRestakeDelegatorImpl);

//         address fullRestakeDelegatorImpl = address(
//             new FullRestakeDelegator(
//                 address(networkRegistry),
//                 address(vaultFactory),
//                 address(operatorVaultOptInService),
//                 address(operatorNetworkOptInService),
//                 address(delegatorFactory)
//             )
//         );
//         delegatorFactory.whitelist(fullRestakeDelegatorImpl);

//         address networkRestakeDelegator =
//             delegatorFactory.create(0, abi.encode(INetworkRestakeDelegator.InitParams(address(vaultFactory))));
//         assertEq(IEntity(networkRestakeDelegator).FACTORY(), address(delegatorFactory));
//         address fullRestakeDelegator = delegatorFactory.create(1, "");
//         assertEq(IEntity(fullRestakeDelegatorImpl).FACTORY(), address(delegatorFactory));
//     }
// }

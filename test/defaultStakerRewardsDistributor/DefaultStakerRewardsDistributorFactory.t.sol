// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.25;

// import {Test, console2} from "forge-std/Test.sol";

// import {VaultFactory} from "src/contracts/VaultFactory.sol";
// import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
// import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
// import {MetadataService} from "src/contracts/service/MetadataService.sol";
// import {NetworkMiddlewareService} from "src/contracts/service/NetworkMiddlewareService.sol";
// import {OptInService} from "src/contracts/service/OptInService.sol";

// import {DefaultStakerRewardsDistributorFactory} from
//     "src/contracts/defaultStakerRewardsDistributor/DefaultStakerRewardsDistributorFactory.sol";
// import {DefaultStakerRewardsDistributor} from "src/contracts/defaultStakerRewardsDistributor/DefaultStakerRewardsDistributor.sol";
// import {IDefaultStakerRewardsDistributor} from "src/interfaces/defaultStakerRewardsDistributor/IDefaultStakerRewardsDistributor.sol";

// import {Vault} from "src/contracts/vault/Vault.sol";
// import {IVault} from "src/interfaces/vault/IVault.sol";

// contract DefaultStakerRewardsDistributorFactoryTest is Test {
//     address owner;
//     address alice;
//     uint256 alicePrivateKey;
//     address bob;
//     uint256 bobPrivateKey;

//     DefaultStakerRewardsDistributorFactory defaultStakerRewardsDistributorFactory;
//     DefaultStakerRewardsDistributor defaultStakerRewardsDistributor;

//     VaultFactory vaultFactory;
//     NetworkRegistry networkRegistry;
//     OperatorRegistry operatorRegistry;
//     MetadataService operatorMetadataService;
//     MetadataService networkMetadataService;
//     NetworkMiddlewareService networkMiddlewareService;
//     OptInService networkVaultOptInService;
//     OptInService operatorVaultOptInService;
//     OptInService operatorNetworkOptInService;

//     IVault vault;

//     function setUp() public {
//         owner = address(this);
//         (alice, alicePrivateKey) = makeAddrAndKey("alice");
//         (bob, bobPrivateKey) = makeAddrAndKey("bob");

//         vaultFactory = new VaultFactory(owner);
//         networkRegistry = new NetworkRegistry();
//         operatorRegistry = new OperatorRegistry();
//         operatorMetadataService = new MetadataService(address(operatorRegistry));
//         networkMetadataService = new MetadataService(address(networkRegistry));
//         networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
//         networkVaultOptInService = new OptInService(address(networkRegistry), address(vaultFactory));
//         operatorVaultOptInService = new OptInService(address(operatorRegistry), address(vaultFactory));
//         operatorNetworkOptInService = new OptInService(address(operatorRegistry), address(networkRegistry));

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

//         vault = IVault(
//             vaultFactory.create(
//                 vaultFactory.lastVersion(),
//                 alice,
//                 abi.encode(
//                     IVault.InitParams({
//                         collateral: address(0),
//                         epochDuration: 1,
//                         vetoDuration: 0,
//                         executeDuration: 0,
//                         stakerRewardsDistributor: address(0),
//                         adminFee: 0,
//                         depositWhitelist: false
//                     })
//                 )
//             )
//         );
//     }

//     function test_Create() public {
//         defaultStakerRewardsDistributorFactory = new DefaultStakerRewardsDistributorFactory(
//             address(networkRegistry), address(vaultFactory), address(networkMiddlewareService)
//         );

//         address defaultStakerRewardsDistributorAddress = defaultStakerRewardsDistributorFactory.create(address(vault));
//         defaultStakerRewardsDistributor = DefaultStakerRewardsDistributor(defaultStakerRewardsDistributorAddress);
//         assertEq(defaultStakerRewardsDistributorFactory.isEntity(defaultStakerRewardsDistributorAddress), true);

//         assertEq(defaultStakerRewardsDistributor.NETWORK_REGISTRY(), address(networkRegistry));
//         assertEq(defaultStakerRewardsDistributor.VAULT_FACTORY(), address(vaultFactory));
//         assertEq(defaultStakerRewardsDistributor.NETWORK_MIDDLEWARE_SERVICE(), address(networkMiddlewareService));
//         assertEq(defaultStakerRewardsDistributor.VAULT(), address(vault));
//         assertEq(defaultStakerRewardsDistributor.version(), 1);
//         assertEq(defaultStakerRewardsDistributor.isNetworkWhitelisted(alice), false);
//         assertEq(defaultStakerRewardsDistributor.rewardsLength(alice), 0);
//         vm.expectRevert();
//         defaultStakerRewardsDistributor.rewards(alice, 0);
//         assertEq(defaultStakerRewardsDistributor.lastUnclaimedReward(alice, alice), 0);
//         assertEq(defaultStakerRewardsDistributor.claimableAdminFee(alice), 0);
//     }

//     function test_CreateRevertNotVault() public {
//         defaultStakerRewardsDistributorFactory = new DefaultStakerRewardsDistributorFactory(
//             address(networkRegistry), address(vaultFactory), address(networkMiddlewareService)
//         );

//         vm.expectRevert(IDefaultStakerRewardsDistributor.NotVault.selector);
//         defaultStakerRewardsDistributorFactory.create(address(0));
//     }
// }

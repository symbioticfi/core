// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {MetadataService} from "src/contracts/MetadataService.sol";
import {MiddlewareService} from "src/contracts/MiddlewareService.sol";
import {NetworkOptInService} from "src/contracts/NetworkOptInService.sol";
import {OperatorOptInService} from "src/contracts/OperatorOptInService.sol";

import {DefaultRewardsDistributorFactory} from
    "src/contracts/defaultRewardsDistributor/DefaultRewardsDistributorFactory.sol";
import {DefaultRewardsDistributor} from "src/contracts/defaultRewardsDistributor/DefaultRewardsDistributor.sol";
import {IDefaultRewardsDistributor} from "src/interfaces/defaultRewardsDistributor/IDefaultRewardsDistributor.sol";

import {Vault} from "src/contracts/vault/v1/Vault.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";

contract DefaultRewardsDistributorFactoryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    DefaultRewardsDistributorFactory defaultRewardsDistributorFactory;
    DefaultRewardsDistributor defaultRewardsDistributor;

    VaultFactory vaultFactory;
    NetworkRegistry networkRegistry;
    OperatorRegistry operatorRegistry;
    MetadataService operatorMetadataService;
    MetadataService networkMetadataService;
    MiddlewareService networkMiddlewareService;
    NetworkOptInService networkVaultOptInService;
    OperatorOptInService operatorVaultOptInService;
    OperatorOptInService operatorNetworkOptInService;

    IVault vault;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vaultFactory = new VaultFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        operatorMetadataService = new MetadataService(address(operatorRegistry));
        networkMetadataService = new MetadataService(address(networkRegistry));
        networkMiddlewareService = new MiddlewareService(address(networkRegistry));
        networkVaultOptInService = new NetworkOptInService(address(networkRegistry), address(vaultFactory));
        operatorVaultOptInService = new OperatorOptInService(address(operatorRegistry), address(vaultFactory));
        operatorNetworkOptInService = new OperatorOptInService(address(operatorRegistry), address(networkRegistry));

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

        vault = IVault(
            vaultFactory.create(
                vaultFactory.lastVersion(),
                abi.encode(
                    IVault.InitParams({
                        owner: alice,
                        collateral: address(0),
                        epochDuration: 1,
                        vetoDuration: 0,
                        slashDuration: 0,
                        rewardsDistributor: address(0),
                        adminFee: 0,
                        depositWhitelist: false
                    })
                )
            )
        );
    }

    function test_Create() public {
        defaultRewardsDistributorFactory = new DefaultRewardsDistributorFactory(
            address(networkRegistry), address(vaultFactory), address(networkMiddlewareService)
        );

        address defaultRewardsDistributorAddress = defaultRewardsDistributorFactory.create(address(vault));
        defaultRewardsDistributor = DefaultRewardsDistributor(defaultRewardsDistributorAddress);
        assertEq(defaultRewardsDistributorFactory.isEntity(defaultRewardsDistributorAddress), true);

        assertEq(defaultRewardsDistributor.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(defaultRewardsDistributor.VAULT_FACTORY(), address(vaultFactory));
        assertEq(defaultRewardsDistributor.NETWORK_MIDDLEWARE_SERVICE(), address(networkMiddlewareService));
        assertEq(defaultRewardsDistributor.VAULT(), address(vault));
        assertEq(defaultRewardsDistributor.version(), 1);
        assertEq(defaultRewardsDistributor.isNetworkWhitelisted(alice), false);
        assertEq(defaultRewardsDistributor.rewardsLength(alice), 0);
        vm.expectRevert();
        defaultRewardsDistributor.rewards(alice, 0);
        assertEq(defaultRewardsDistributor.lastUnclaimedReward(alice, alice), 0);
        assertEq(defaultRewardsDistributor.claimableAdminFee(alice), 0);
    }

    function test_CreateRevertNotVault() public {
        defaultRewardsDistributorFactory = new DefaultRewardsDistributorFactory(
            address(networkRegistry), address(vaultFactory), address(networkMiddlewareService)
        );

        vm.expectRevert(IDefaultRewardsDistributor.NotVault.selector);
        defaultRewardsDistributorFactory.create(address(0));
    }
}

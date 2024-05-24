// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {MigratablesFactory} from "src/contracts/base/MigratablesFactory.sol";
import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {MetadataPlugin} from "src/contracts/MetadataPlugin.sol";
import {MiddlewarePlugin} from "src/contracts/MiddlewarePlugin.sol";
import {NetworkOptInPlugin} from "src/contracts/NetworkOptInPlugin.sol";
import {OperatorOptInPlugin} from "src/contracts/OperatorOptInPlugin.sol";

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

    NonMigratablesRegistry operatorRegistry;
    MigratablesFactory vaultRegistry;
    NonMigratablesRegistry networkRegistry;
    MetadataPlugin operatorMetadataPlugin;
    MetadataPlugin networkMetadataPlugin;
    MiddlewarePlugin networkMiddlewarePlugin;
    NetworkOptInPlugin networkVaultOptInPlugin;
    OperatorOptInPlugin operatorVaultOptInPlugin;
    OperatorOptInPlugin operatorNetworkOptInPlugin;

    IVault vault;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        operatorRegistry = new NonMigratablesRegistry();
        vaultRegistry = new MigratablesFactory(owner);
        networkRegistry = new NonMigratablesRegistry();
        operatorMetadataPlugin = new MetadataPlugin(address(operatorRegistry));
        networkMetadataPlugin = new MetadataPlugin(address(networkRegistry));
        networkMiddlewarePlugin = new MiddlewarePlugin(address(networkRegistry));
        networkVaultOptInPlugin = new NetworkOptInPlugin(address(networkRegistry), address(vaultRegistry));
        operatorVaultOptInPlugin = new OperatorOptInPlugin(address(operatorRegistry), address(vaultRegistry));
        operatorNetworkOptInPlugin = new OperatorOptInPlugin(address(operatorRegistry), address(networkRegistry));

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

        vault = IVault(
            vaultRegistry.create(
                vaultRegistry.lastVersion(),
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

    function test_Create(uint256 initialLimit, address limitIncreaser) public {
        defaultRewardsDistributorFactory =
            new DefaultRewardsDistributorFactory(address(networkRegistry), address(vaultRegistry));

        address defaultRewardsDistributorAddress = defaultRewardsDistributorFactory.create(address(vault));
        defaultRewardsDistributor = DefaultRewardsDistributor(defaultRewardsDistributorAddress);
        assertEq(defaultRewardsDistributorFactory.isEntity(defaultRewardsDistributorAddress), true);

        assertEq(defaultRewardsDistributor.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(defaultRewardsDistributor.VAULT_REGISTRY(), address(vaultRegistry));
        assertEq(defaultRewardsDistributor.VAULT(), address(vault));
        assertEq(defaultRewardsDistributor.version(), 1);
        assertEq(defaultRewardsDistributor.rewardsLength(alice), 0);
        vm.expectRevert();
        defaultRewardsDistributor.rewards(alice, 0);
        assertEq(defaultRewardsDistributor.lastUnclaimedReward(alice, alice), 0);
        assertEq(defaultRewardsDistributor.claimableAdminFee(alice), 0);
    }

    function test_CreateRevertNotVault() public {
        defaultRewardsDistributorFactory =
            new DefaultRewardsDistributorFactory(address(networkRegistry), address(vaultRegistry));

        vm.expectRevert(IDefaultRewardsDistributor.NotVault.selector);
        defaultRewardsDistributorFactory.create(address(0));
    }
}

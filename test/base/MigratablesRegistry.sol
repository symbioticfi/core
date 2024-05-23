// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {MigratablesRegistry} from "src/contracts/base/MigratablesRegistry.sol";
import {IMigratablesRegistry} from "src/interfaces/base/IMigratablesRegistry.sol";

import {IMigratableEntity} from "src/interfaces/base/IMigratableEntity.sol";

import {SimpleMigratableEntity} from "test/mocks/SimpleMigratableEntity.sol";
import {SimpleMigratableEntityV2} from "test/mocks/SimpleMigratableEntityV2.sol";

contract MigratablesRegistryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    IMigratablesRegistry registry;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        registry = new MigratablesRegistry(owner);
    }

    function test_Create() public {
        assertEq(registry.lastVersion(), 0);
        vm.expectRevert();
        registry.implementation(0);

        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        assertEq(registry.lastVersion(), 1);
        assertEq(registry.implementation(1), impl);

        impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        assertEq(registry.lastVersion(), 2);
        assertEq(registry.implementation(2), impl);

        assertEq(registry.isEntity(alice), false);
        address entity = registry.create(2, abi.encode(alice));
        assertEq(registry.isEntity(entity), true);
        assertEq(IMigratableEntity(entity).version(), 2);

        vm.startPrank(alice);
        vm.expectRevert();
        registry.migrate(alice, abi.encode(0));
        vm.stopPrank();
    }

    function test_Migrate(uint256 a1, uint256 a2, uint256 b1, uint256 b2) public {
        a2 = bound(a2, 0, type(uint256).max - 1);

        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        address entity = registry.create(2, abi.encode(alice));

        address implV2 = address(new SimpleMigratableEntityV2());
        registry.whitelist(implV2);

        assertEq(registry.lastVersion(), 3);
        assertEq(registry.implementation(3), implV2);

        SimpleMigratableEntity(entity).setA(a1);
        assertEq(SimpleMigratableEntity(entity).a(), a1);

        vm.startPrank(alice);
        registry.migrate(entity, abi.encode(b1));
        vm.stopPrank();

        assertEq(IMigratableEntity(entity).version(), 3);
        assertEq(SimpleMigratableEntityV2(entity).a(), a1);
        assertEq(SimpleMigratableEntityV2(entity).b(), b1);

        SimpleMigratableEntityV2(entity).setA(a2);
        SimpleMigratableEntityV2(entity).setB(b2);
        assertEq(SimpleMigratableEntityV2(entity).a(), a2 + 1);
        assertEq(SimpleMigratableEntityV2(entity).b(), b2);
    }

    function test_WhitelistRevertAlreadyWhitelisted() public {
        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        vm.expectRevert(IMigratablesRegistry.AlreadyWhitelisted.selector);
        registry.whitelist(impl);
    }

    function test_CreateRevertInvalidVersion1() public {
        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        vm.expectRevert(IMigratablesRegistry.InvalidVersion.selector);
        registry.create(0, abi.encode(alice));

        vm.expectRevert(IMigratablesRegistry.InvalidVersion.selector);
        registry.create(2, abi.encode(alice));

        vm.expectRevert(IMigratablesRegistry.InvalidVersion.selector);
        registry.create(3, abi.encode(alice));
    }

    function test_MigrateRevertImproperOwner() public {
        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        address entity = registry.create(1, abi.encode(alice));

        address implV2 = address(new SimpleMigratableEntityV2());
        registry.whitelist(implV2);

        vm.startPrank(bob);
        vm.expectRevert(IMigratablesRegistry.NotOwner.selector);
        registry.migrate(entity, abi.encode(0));
        vm.stopPrank();
    }

    function test_MigrateRevertInvalidVersion2() public {
        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        address entity = registry.create(1, abi.encode(alice));

        address implV2 = address(new SimpleMigratableEntityV2());
        registry.whitelist(implV2);

        vm.startPrank(alice);
        registry.migrate(entity, abi.encode(0));
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMigratablesRegistry.InvalidVersion.selector);
        registry.migrate(entity, abi.encode(0));
        vm.stopPrank();
    }

    function test_MigrateRevertNotProxyAdmin() public {
        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        address entity = registry.create(1, abi.encode(alice));

        address implV2 = address(new SimpleMigratableEntityV2());
        registry.whitelist(implV2);

        vm.startPrank(alice);
        registry.migrate(entity, abi.encode(0));
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMigratableEntity.NotProxyAdmin.selector);
        IMigratableEntity(entity).migrate(abi.encode(0));
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {MigratablesRegistry} from "src/contracts/MigratablesRegistry.sol";
import {IMigratablesRegistry} from "src/interfaces/IMigratablesRegistry.sol";

import {IMigratableEntity} from "src/interfaces/IMigratableEntity.sol";

import {SimpleMigratableEntity} from "./mocks/SimpleMigratableEntity.sol";
import {SimpleMigratableEntityV2} from "./mocks/SimpleMigratableEntityV2.sol";

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
        assertEq(registry.maxVersion(), 0);
        vm.expectRevert();
        registry.version(alice);

        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        assertEq(registry.maxVersion(), 1);

        assertEq(registry.isEntity(alice), false);
        address entity = registry.create(1, abi.encode(alice));
        assertEq(registry.isEntity(entity), true);
        assertEq(registry.version(entity), 1);

        vm.startPrank(alice);
        vm.expectRevert();
        registry.migrate(alice, "");
        vm.stopPrank();
    }

    function test_Migrate() public {
        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        address entity = registry.create(1, abi.encode(alice));

        address implV2 = address(new SimpleMigratableEntityV2());
        registry.whitelist(implV2);

        assertEq(registry.maxVersion(), 2);

        SimpleMigratableEntity(entity).setA(42);
        assertEq(SimpleMigratableEntity(entity).a(), 42);

        vm.startPrank(alice);
        registry.migrate(entity, "");
        vm.stopPrank();

        assertEq(registry.version(entity), 2);
        assertEq(SimpleMigratableEntityV2(entity).a(), 42);
        assertEq(SimpleMigratableEntityV2(entity).b(), 0);

        SimpleMigratableEntityV2(entity).setA(43);
        SimpleMigratableEntityV2(entity).setB(44);
        assertEq(SimpleMigratableEntityV2(entity).a(), 44);
        assertEq(SimpleMigratableEntityV2(entity).b(), 44);
    }

    function test_WhitelistRevertAlreadyWhitelisted() public {
        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        vm.expectRevert(IMigratablesRegistry.AlreadyWhitelisted.selector);
        registry.whitelist(impl);
    }

    function test_CreateRevertInvalidVersion() public {
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
        vm.expectRevert(IMigratablesRegistry.ImproperOwner.selector);
        registry.migrate(entity, "");
        vm.stopPrank();
    }

    function test_MigrateRevertAlreadyUpToDate() public {
        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        address entity = registry.create(1, abi.encode(alice));

        address implV2 = address(new SimpleMigratableEntityV2());
        registry.whitelist(implV2);

        vm.startPrank(alice);
        registry.migrate(entity, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMigratablesRegistry.AlreadyUpToDate.selector);
        registry.migrate(entity, "");
        vm.stopPrank();
    }

    function test_MigrateRevertNotProxyAdmin() public {
        address impl = address(new SimpleMigratableEntity());
        registry.whitelist(impl);

        address entity = registry.create(1, abi.encode(alice));

        address implV2 = address(new SimpleMigratableEntityV2());
        registry.whitelist(implV2);

        vm.startPrank(alice);
        registry.migrate(entity, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMigratableEntity.NotProxyAdmin.selector);
        IMigratableEntity(entity).migrate("");
        vm.stopPrank();
    }
}

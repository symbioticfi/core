// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {IRegistry} from "src/interfaces/common/IRegistry.sol";

import {MigratablesFactory} from "src/contracts/common/MigratablesFactory.sol";
import {IMigratablesFactory} from "src/interfaces/common/IMigratablesFactory.sol";

import {IMigratableEntity} from "src/interfaces/common/IMigratableEntity.sol";

import {MigratableEntityProxy} from "src/contracts/common/MigratableEntityProxy.sol";

import {SimpleMigratableEntity} from "test/mocks/SimpleMigratableEntity.sol";
import {SimpleMigratableEntityV2} from "test/mocks/SimpleMigratableEntityV2.sol";

contract MigratablesFactoryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    IMigratablesFactory factory;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        factory = new MigratablesFactory(owner);
    }

    function test_Create() public {
        assertEq(factory.lastVersion(), 0);
        vm.expectRevert();
        factory.implementation(0);

        address impl = address(new SimpleMigratableEntity(address(factory)));
        assertEq(IMigratableEntity(impl).FACTORY(), address(factory));
        factory.whitelist(impl);

        assertEq(factory.lastVersion(), 1);
        assertEq(factory.implementation(1), impl);

        impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        assertEq(factory.lastVersion(), 2);
        assertEq(factory.implementation(2), impl);

        assertEq(factory.isEntity(alice), false);
        address entity = factory.create(2, alice, "");
        assertEq(factory.isEntity(entity), true);
        assertEq(IMigratableEntity(entity).version(), 2);

        impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        vm.startPrank(alice);
        uint64 lastVersion = factory.lastVersion();
        vm.expectRevert(IRegistry.EntityNotExist.selector);
        factory.migrate(alice, lastVersion, abi.encode(0));
        vm.stopPrank();
    }

    function test_CreateRevertInvalidVersion() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        vm.expectRevert(IMigratablesFactory.InvalidVersion.selector);
        factory.create(0, alice, "");

        vm.expectRevert(IMigratablesFactory.InvalidVersion.selector);
        factory.create(2, alice, "");

        vm.expectRevert(IMigratablesFactory.InvalidVersion.selector);
        factory.create(3, alice, "");
    }

    function test_ReinitRevertNotFactory() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        address entity = factory.create(1, alice, "");

        vm.expectRevert(IMigratableEntity.NotFactory.selector);
        SimpleMigratableEntity(entity).initialize(2, alice, abi.encode(0));
    }

    function test_Migrate(uint256 a1, uint256 a2, uint256 b1, uint256 b2) public {
        a2 = bound(a2, 0, type(uint256).max - 1);

        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        address entity = factory.create(2, alice, "");

        address implV2 = address(new SimpleMigratableEntityV2(address(factory)));
        factory.whitelist(implV2);

        assertEq(factory.lastVersion(), 3);
        assertEq(factory.implementation(3), implV2);

        SimpleMigratableEntity(entity).setA(a1);
        assertEq(SimpleMigratableEntity(entity).a(), a1);

        vm.startPrank(alice);
        factory.migrate(entity, factory.lastVersion(), abi.encode(b1));
        vm.stopPrank();

        assertEq(IMigratableEntity(entity).version(), 3);
        assertEq(SimpleMigratableEntityV2(entity).a(), a1);
        assertEq(SimpleMigratableEntityV2(entity).b(), b1);

        SimpleMigratableEntityV2(entity).setA(a2);
        SimpleMigratableEntityV2(entity).setB(b2);
        assertEq(SimpleMigratableEntityV2(entity).a(), a2 + 1);
        assertEq(SimpleMigratableEntityV2(entity).b(), b2);

        vm.startPrank(alice);
        vm.expectRevert(MigratableEntityProxy.ProxyDeniedAdminAccess.selector);
        MigratableEntityProxy(payable(entity)).upgradeToAndCall(impl, "");
        vm.stopPrank();
    }

    function test_MigrateRevertImproperOwner() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        address entity = factory.create(1, alice, "");

        address implV2 = address(new SimpleMigratableEntityV2(address(factory)));
        factory.whitelist(implV2);

        vm.startPrank(bob);
        uint64 lastVersion = factory.lastVersion();
        vm.expectRevert(IMigratablesFactory.NotOwner.selector);
        factory.migrate(entity, lastVersion, abi.encode(0));
        vm.stopPrank();
    }

    function test_MigrateRevertInvalidVersion() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        address entity = factory.create(1, alice, "");

        address implV2 = address(new SimpleMigratableEntityV2(address(factory)));
        factory.whitelist(implV2);

        vm.startPrank(alice);
        uint64 lastVersion = factory.lastVersion();
        vm.expectRevert(IMigratablesFactory.InvalidVersion.selector);
        factory.migrate(entity, lastVersion + 1, abi.encode(0));
        vm.stopPrank();
    }

    function test_MigrateRevertOldVersion() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        address entity = factory.create(1, alice, "");

        address implV2 = address(new SimpleMigratableEntityV2(address(factory)));
        factory.whitelist(implV2);

        vm.startPrank(alice);
        vm.expectRevert(IMigratablesFactory.OldVersion.selector);
        factory.migrate(entity, 1, abi.encode(0));
        vm.stopPrank();
    }

    function test_MigrateRevertNotFactory() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        address entity = factory.create(1, alice, "");

        address implV2 = address(new SimpleMigratableEntityV2(address(factory)));
        factory.whitelist(implV2);

        vm.startPrank(alice);
        uint64 lastVersion = factory.lastVersion();
        vm.expectRevert(IMigratableEntity.NotFactory.selector);
        IMigratableEntity(entity).migrate(lastVersion, abi.encode(0));
        vm.stopPrank();
    }

    function test_WhitelistRevertAlreadyWhitelisted() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        vm.expectRevert(IMigratablesFactory.AlreadyWhitelisted.selector);
        factory.whitelist(impl);
    }
}

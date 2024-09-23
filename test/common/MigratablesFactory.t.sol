// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {IRegistry} from "../../src/interfaces/common/IRegistry.sol";

import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {IMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";

import {SimpleMigratableEntity} from "../mocks/SimpleMigratableEntity.sol";
import {SimpleMigratableEntityV2} from "../mocks/SimpleMigratableEntityV2.sol";

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
        factory.whitelist(impl);

        assertEq(factory.lastVersion(), 1);
        assertEq(factory.implementation(1), impl);
        assertEq(factory.blacklisted(1), false);

        impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        assertEq(factory.lastVersion(), 2);
        assertEq(factory.implementation(2), impl);
        assertEq(factory.blacklisted(2), false);

        assertEq(factory.isEntity(alice), false);
        address entity = factory.create(2, alice, "");
        assertEq(factory.isEntity(entity), true);

        impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        vm.startPrank(alice);
        uint64 lastVersion = factory.lastVersion();
        vm.expectRevert(IRegistry.EntityNotExist.selector);
        factory.migrate(alice, lastVersion, abi.encode(0));
        vm.stopPrank();

        factory.blacklist(2);

        assertEq(factory.blacklisted(2), true);
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

    function test_Migrate(
        uint256 a
    ) public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        address entity = factory.create(2, alice, "");

        address implV2 = address(new SimpleMigratableEntityV2(address(factory)));
        factory.whitelist(implV2);

        assertEq(factory.lastVersion(), 3);
        assertEq(factory.implementation(3), implV2);

        vm.startPrank(alice);
        factory.migrate(entity, factory.lastVersion(), abi.encode(a));
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

    function test_WhitelistRevertInvalidImplementation() public {
        address impl = address(new SimpleMigratableEntity(address(address(1))));
        vm.expectRevert(IMigratablesFactory.InvalidImplementation.selector);
        factory.whitelist(impl);
    }

    function test_WhitelistRevertAlreadyWhitelisted() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        vm.expectRevert(IMigratablesFactory.AlreadyWhitelisted.selector);
        factory.whitelist(impl);
    }

    function test_BlacklistRevertAlreadyBlacklisted() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        factory.blacklist(1);

        vm.expectRevert(IMigratablesFactory.AlreadyBlacklisted.selector);
        factory.blacklist(1);
    }

    function test_BlacklistRevertInvalidVersion() public {
        vm.expectRevert(IMigratablesFactory.InvalidVersion.selector);
        factory.blacklist(0);
    }
}

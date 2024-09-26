// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {IRegistry} from "../../src/interfaces/common/IRegistry.sol";

import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {IMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";
import {IMigratableEntityProxy} from "../../src/interfaces/common/IMigratableEntityProxy.sol";

import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";

import {MigratableEntityProxy} from "../../src/contracts/common/MigratableEntityProxy.sol";

import {SimpleMigratableEntity} from "../mocks/SimpleMigratableEntity.sol";
import {SimpleMigratableEntityV2} from "../mocks/SimpleMigratableEntityV2.sol";

contract MigratableEntityTest is Test {
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
        address impl = address(new SimpleMigratableEntity(address(factory)));
        assertEq(IMigratableEntity(impl).FACTORY(), address(factory));
        factory.whitelist(impl);

        address entity = factory.create(1, alice, "");
        assertEq(IMigratableEntity(entity).FACTORY(), address(factory));
        assertEq(IMigratableEntity(entity).version(), 1);
    }

    function test_ReinitRevertAlreadyInitialized() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        address entity = factory.create(1, alice, "");

        vm.expectRevert(IMigratableEntity.AlreadyInitialized.selector);
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
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {Factory} from "src/contracts/common/Factory.sol";
import {IFactory} from "src/interfaces/common/IFactory.sol";

import {IEntity} from "src/interfaces/common/IEntity.sol";

import {SimpleEntity} from "test/mocks/SimpleEntity.sol";

contract FactoryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    IFactory factory;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        factory = new Factory(owner);
    }

    function test_Create() public {
        assertEq(factory.totalImplementations(), 0);
        vm.expectRevert();
        factory.implementation(0);

        address impl = address(new SimpleEntity(address(factory)));
        factory.whitelist(impl);

        assertEq(factory.totalImplementations(), 1);
        assertEq(factory.implementation(0), impl);

        impl = address(new SimpleEntity(address(factory)));
        factory.whitelist(impl);

        assertEq(factory.totalImplementations(), 2);
        assertEq(factory.implementation(1), impl);

        assertEq(factory.isEntity(alice), false);
        address entity = factory.create(1, true, "");
        assertEq(factory.isEntity(entity), true);
    }

    function test_CreateRevertInvalidIndex() public {
        address impl = address(new SimpleEntity(address(factory)));
        factory.whitelist(impl);

        impl = address(new SimpleEntity(address(factory)));
        factory.whitelist(impl);

        vm.expectRevert();
        factory.create(2, true, "");

        vm.expectRevert();
        factory.create(3, true, "");
    }

    function test_WhitelistRevertInvalidImplementation() public {
        address impl = address(new SimpleEntity(address(address(1))));
        vm.expectRevert(IFactory.InvalidImplementation.selector);
        factory.whitelist(impl);
    }

    function test_WhitelistRevertAlreadyWhitelisted() public {
        address impl = address(new SimpleEntity(address(factory)));
        factory.whitelist(impl);

        vm.expectRevert(IFactory.AlreadyWhitelisted.selector);
        factory.whitelist(impl);
    }
}

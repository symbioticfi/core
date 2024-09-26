// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {Factory} from "../../src/contracts/common/Factory.sol";
import {IFactory} from "../../src/interfaces/common/IFactory.sol";

import {IEntity} from "../../src/interfaces/common/IEntity.sol";

import {SimpleEntity} from "../mocks/SimpleEntity.sol";
import {FakeEntity} from "../mocks/FakeEntity.sol";

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
        assertEq(factory.totalTypes(), 0);
        vm.expectRevert();
        factory.implementation(0);

        address impl = address(new SimpleEntity(address(factory), factory.totalTypes()));
        factory.whitelist(impl);

        assertEq(factory.totalTypes(), 1);
        assertEq(factory.implementation(0), impl);
        assertEq(factory.blacklisted(0), false);

        impl = address(new SimpleEntity(address(factory), factory.totalTypes()));
        factory.whitelist(impl);

        assertEq(factory.totalTypes(), 2);
        assertEq(factory.implementation(1), impl);
        assertEq(factory.blacklisted(1), false);

        assertEq(factory.isEntity(alice), false);
        address entity = factory.create(1, "");
        assertEq(factory.isEntity(entity), true);

        factory.blacklist(1);

        assertEq(factory.blacklisted(1), true);
    }

    function test_CreateRevertInvalidIndex() public {
        address impl = address(new SimpleEntity(address(factory), factory.totalTypes()));
        factory.whitelist(impl);

        impl = address(new SimpleEntity(address(factory), factory.totalTypes()));
        factory.whitelist(impl);

        vm.expectRevert();
        factory.create(2, "");

        vm.expectRevert();
        factory.create(3, "");
    }

    function test_WhitelistRevertInvalidImplementation1() public {
        address impl = address(new SimpleEntity(address(address(1)), factory.totalTypes()));
        vm.expectRevert(IFactory.InvalidImplementation.selector);
        factory.whitelist(impl);
    }

    function test_WhitelistRevertInvalidImplementation2() public {
        address impl = address(new SimpleEntity(address(factory), factory.totalTypes()));
        factory.whitelist(impl);

        impl = address(new SimpleEntity(address(factory), factory.totalTypes() - 1));
        vm.expectRevert(IFactory.InvalidImplementation.selector);
        factory.whitelist(impl);
    }

    function test_WhitelistRevertAlreadyWhitelisted() public {
        address impl = address(new FakeEntity(address(factory), factory.totalTypes()));
        factory.whitelist(impl);

        FakeEntity(impl).setType(factory.totalTypes());
        vm.expectRevert(IFactory.AlreadyWhitelisted.selector);
        factory.whitelist(impl);
    }

    function test_BlacklistRevertAlreadyBlacklisted() public {
        address impl = address(new SimpleEntity(address(factory), factory.totalTypes()));
        factory.whitelist(impl);

        factory.blacklist(0);
        vm.expectRevert(IFactory.AlreadyBlacklisted.selector);
        factory.blacklist(0);
    }

    function test_BlacklistRevertIinvalidType() public {
        vm.expectRevert(IFactory.InvalidType.selector);
        factory.blacklist(0);
    }
}

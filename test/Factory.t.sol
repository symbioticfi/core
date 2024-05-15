// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {SimpleFactory} from "./mocks/SimpleFactory.sol";

contract FactoryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    SimpleFactory factory;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        factory = new SimpleFactory();
    }

    function test_Create() public {
        assertEq(factory.totalEntities(), 0);
        assertEq(factory.isEntity(alice), false);
        vm.expectRevert();
        factory.entity(0);

        vm.startPrank(alice);
        address entity = factory.create();
        vm.stopPrank();

        assertEq(entity, alice);
        assertEq(factory.totalEntities(), 1);
        assertEq(factory.isEntity(alice), true);
        assertEq(factory.entity(0), alice);
        vm.expectRevert();
        factory.entity(1);

        vm.startPrank(bob);
        entity = factory.create();
        vm.stopPrank();

        assertEq(entity, bob);
        assertEq(factory.totalEntities(), 2);
        assertEq(factory.isEntity(alice), true);
        assertEq(factory.isEntity(bob), true);
        assertEq(factory.entity(0), alice);
        assertEq(factory.entity(1), bob);
        vm.expectRevert();
        factory.entity(2);
    }
}

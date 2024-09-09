// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {SimpleRegistry} from "../mocks/SimpleRegistry.sol";

contract FactoryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    SimpleRegistry registry;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        registry = new SimpleRegistry();
    }

    function test_Create() public {
        assertEq(registry.totalEntities(), 0);
        assertEq(registry.isEntity(alice), false);
        vm.expectRevert();
        registry.entity(0);

        vm.startPrank(alice);
        address entity = registry.register();
        vm.stopPrank();

        assertEq(entity, alice);
        assertEq(registry.totalEntities(), 1);
        assertEq(registry.isEntity(alice), true);
        assertEq(registry.entity(0), alice);
        vm.expectRevert();
        registry.entity(1);

        vm.startPrank(bob);
        entity = registry.register();
        vm.stopPrank();

        assertEq(entity, bob);
        assertEq(registry.totalEntities(), 2);
        assertEq(registry.isEntity(alice), true);
        assertEq(registry.isEntity(bob), true);
        assertEq(registry.entity(0), alice);
        assertEq(registry.entity(1), bob);
        vm.expectRevert();
        registry.entity(2);
    }
}

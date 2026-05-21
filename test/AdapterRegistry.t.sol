// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterRegistry} from "../src/contracts/AdapterRegistry.sol";
import {IAdapterRegistry} from "../src/interfaces/IAdapterRegistry.sol";

contract AdapterRegistryTest is Test {
    AdapterRegistry internal registry;
    address internal owner;
    address internal alice;
    address internal adapter;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        adapter = makeAddr("adapter");
        registry = new AdapterRegistry();
        registry.initialize(owner);
    }

    function test_whitelistAdapterFactory() public {
        vm.prank(owner);
        registry.whitelistAdapterFactory(adapter);

        assertTrue(registry.isEntity(adapter));
    }

    function test_whitelistAdapterFactoryRevertAdapterAlreadyWhitelisted() public {
        vm.startPrank(owner);
        registry.whitelistAdapterFactory(adapter);
        vm.expectRevert(IAdapterRegistry.AdapterFactoryAlreadyWhitelisted.selector);
        registry.whitelistAdapterFactory(adapter);
        vm.stopPrank();
    }

    function test_whitelistAdapterFactoryRevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.whitelistAdapterFactory(adapter);
    }
}

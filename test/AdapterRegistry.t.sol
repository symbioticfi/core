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
        registry = new AdapterRegistry(owner);
    }

    function test_whitelistAdapter() public {
        vm.prank(owner);
        registry.whitelistAdapter(adapter);

        assertTrue(registry.isEntity(adapter));
    }

    function test_whitelistAdapterRevertAdapterAlreadyWhitelisted() public {
        vm.startPrank(owner);
        registry.whitelistAdapter(adapter);
        vm.expectRevert(IAdapterRegistry.AdapterAlreadyWhitelisted.selector);
        registry.whitelistAdapter(adapter);
        vm.stopPrank();
    }

    function test_whitelistAdapterRevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.whitelistAdapter(adapter);
    }
}

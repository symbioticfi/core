// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterRegistry} from "../src/contracts/AdapterRegistry.sol";

contract AdapterRegistryTest is Test {
    AdapterRegistry internal registry;
    address internal owner;
    address internal alice;
    address internal vault;
    address internal adapter;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        vault = makeAddr("vault");
        adapter = makeAddr("adapter");
        registry = new AdapterRegistry();
        registry.initialize(owner);
    }

    function test_whitelistAdapterFactory() public {
        vm.prank(owner);
        registry.whitelist(vault, adapter);

        assertTrue(registry.isWhitelisted(vault, adapter));
    }

    function test_whitelistAdapterFactoryCanBeRepeated() public {
        vm.startPrank(owner);
        registry.whitelist(vault, adapter);
        registry.whitelist(vault, adapter);
        vm.stopPrank();

        assertTrue(registry.isWhitelisted(vault, adapter));
    }

    function test_whitelistAdapterFactoryRevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.whitelist(vault, adapter);
    }
}

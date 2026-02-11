// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {PluginRegistry} from "../src/contracts/PluginRegistry.sol";
import {IPluginRegistry} from "../src/interfaces/IPluginRegistry.sol";

contract PluginRegistryTest is Test {
    PluginRegistry internal registry;
    address internal owner;
    address internal alice;
    address internal plugin;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        plugin = makeAddr("plugin");
        registry = new PluginRegistry(owner);
    }

    function test_whitelistPlugin() public {
        vm.prank(owner);
        registry.whitelistPlugin(plugin);

        assertTrue(registry.isEntity(plugin));
    }

    function test_whitelistPluginRevertPluginAlreadyWhitelisted() public {
        vm.startPrank(owner);
        registry.whitelistPlugin(plugin);
        vm.expectRevert(IPluginRegistry.PluginAlreadyWhitelisted.selector);
        registry.whitelistPlugin(plugin);
        vm.stopPrank();
    }

    function test_whitelistPluginRevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.whitelistPlugin(plugin);
    }
}

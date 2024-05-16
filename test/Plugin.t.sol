// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/NonMigratablesRegistry.sol";
import {IPlugin} from "src/interfaces/IPlugin.sol";

import {SimplePlugin} from "./mocks/SimplePlugin.sol";

contract PluginTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry registry;

    SimplePlugin plugin;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        registry = new NonMigratablesRegistry();
    }

    function test_Create(uint256 number) public {
        plugin = new SimplePlugin(address(registry));

        assertEq(plugin.REGISTRY(), address(registry));
        assertEq(plugin.number(alice), 0);

        vm.startPrank(alice);
        registry.register();
        vm.stopPrank();

        vm.startPrank(alice);
        plugin.setNumber(number);
        vm.stopPrank();

        assertEq(plugin.number(alice), number);
    }

    function test_SetNumberRevertNotEntity(uint256 number) public {
        plugin = new SimplePlugin(address(registry));

        vm.startPrank(alice);
        vm.expectRevert(IPlugin.NotEntity.selector);
        plugin.setNumber(number);
        vm.stopPrank();
    }
}

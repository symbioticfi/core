// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {IPlugin} from "src/interfaces/IPlugin.sol";

import {MiddlewarePlugin} from "src/contracts/plugins/MiddlewarePlugin.sol";
import {IMiddlewarePlugin} from "src/interfaces/plugins/IMiddlewarePlugin.sol";

contract MiddlewarePluginTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry registry;

    IMiddlewarePlugin plugin;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        registry = new NonMigratablesRegistry();
    }

    function test_Create(address middleware) public {
        vm.assume(middleware != address(0));

        plugin = IMiddlewarePlugin(address(new MiddlewarePlugin(address(registry))));

        assertEq(plugin.middleware(alice), address(0));

        vm.startPrank(alice);
        registry.register();
        vm.stopPrank();

        vm.startPrank(alice);
        plugin.setMiddleware(middleware);
        vm.stopPrank();

        assertEq(plugin.middleware(alice), middleware);
    }

    function test_SetMiddlewareRevertNotEntity(address middleware) public {
        vm.assume(middleware != address(0));

        plugin = IMiddlewarePlugin(address(new MiddlewarePlugin(address(registry))));

        vm.startPrank(alice);
        vm.expectRevert(IPlugin.NotEntity.selector);
        plugin.setMiddleware(middleware);
        vm.stopPrank();
    }

    function test_SetMiddlewareRevertAlreadySet(address middleware) public {
        vm.assume(middleware != address(0));

        plugin = IMiddlewarePlugin(address(new MiddlewarePlugin(address(registry))));

        vm.startPrank(alice);
        registry.register();
        vm.stopPrank();

        vm.startPrank(alice);
        plugin.setMiddleware(middleware);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMiddlewarePlugin.AlreadySet.selector);
        plugin.setMiddleware(middleware);
        vm.stopPrank();
    }
}

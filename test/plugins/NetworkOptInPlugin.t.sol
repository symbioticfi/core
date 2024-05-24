// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";

import {NetworkOptInPlugin} from "src/contracts/plugins/NetworkOptInPlugin.sol";
import {INetworkOptInPlugin} from "src/interfaces/plugins/INetworkOptInPlugin.sol";

contract OptInPluginTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry networkRegistry;
    NonMigratablesRegistry whereRegistry;

    INetworkOptInPlugin plugin;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        networkRegistry = new NonMigratablesRegistry();
        whereRegistry = new NonMigratablesRegistry();
    }

    function test_Create(address resolver) public {
        plugin = INetworkOptInPlugin(address(new NetworkOptInPlugin(address(networkRegistry), address(whereRegistry))));

        assertEq(plugin.WHERE_REGISTRY(), address(whereRegistry));
        assertEq(plugin.isOptedIn(alice, alice, alice), false);
        assertEq(plugin.lastOptOut(alice, alice, alice), 0);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        address network = alice;
        address where = bob;

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        plugin.optIn(resolver, where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(network, resolver, where), true);
        assertEq(plugin.lastOptOut(network, resolver, where), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(plugin.isOptedIn(network, resolver, where), true);
        assertEq(plugin.lastOptOut(network, resolver, where), 0);

        vm.startPrank(network);
        plugin.optOut(resolver, where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(network, resolver, where), false);
        assertEq(plugin.lastOptOut(network, resolver, where), blockTimestamp);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(plugin.isOptedIn(network, resolver, where), false);
        assertEq(plugin.lastOptOut(network, resolver, where), blockTimestamp - 1);

        vm.startPrank(network);
        plugin.optIn(resolver, where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(network, resolver, where), true);
        assertEq(plugin.lastOptOut(network, resolver, where), blockTimestamp - 1);

        vm.startPrank(network);
        plugin.optOut(resolver, where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(network, resolver, where), false);
        assertEq(plugin.lastOptOut(network, resolver, where), blockTimestamp);
    }

    function test_OptInRevertNotEntity(address resolver) public {
        plugin = INetworkOptInPlugin(address(new NetworkOptInPlugin(address(networkRegistry), address(whereRegistry))));

        address network = alice;
        address where = bob;

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInPlugin.NotNetwork.selector);
        plugin.optIn(resolver, where);
        vm.stopPrank();
    }

    function test_OptInRevertNotWhereEntity(address resolver) public {
        plugin = INetworkOptInPlugin(address(new NetworkOptInPlugin(address(networkRegistry), address(whereRegistry))));

        address network = alice;
        address where = bob;

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInPlugin.NotWhereEntity.selector);
        plugin.optIn(resolver, where);
        vm.stopPrank();
    }

    function test_OptInRevertAlreadyOptedIn(address resolver) public {
        plugin = INetworkOptInPlugin(address(new NetworkOptInPlugin(address(networkRegistry), address(whereRegistry))));

        address network = alice;
        address where = bob;

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        plugin.optIn(resolver, where);
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInPlugin.AlreadyOptedIn.selector);
        plugin.optIn(resolver, where);
        vm.stopPrank();
    }

    function test_OptOutRevertNotOptedIn(address resolver) public {
        plugin = INetworkOptInPlugin(address(new NetworkOptInPlugin(address(networkRegistry), address(whereRegistry))));

        address network = alice;
        address where = bob;

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInPlugin.NotOptedIn.selector);
        plugin.optOut(resolver, where);
        vm.stopPrank();
    }
}

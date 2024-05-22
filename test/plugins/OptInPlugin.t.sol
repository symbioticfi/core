// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {IPlugin} from "src/interfaces/base/IPlugin.sol";

import {OptInPlugin} from "src/contracts/plugins/OptInPlugin.sol";
import {IOptInPlugin} from "src/interfaces/plugins/IOptInPlugin.sol";

contract OptInPluginTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry whoRegistry;
    NonMigratablesRegistry whereRegistry;

    IOptInPlugin plugin;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        whoRegistry = new NonMigratablesRegistry();
        whereRegistry = new NonMigratablesRegistry();
    }

    function test_Create() public {
        plugin = IOptInPlugin(address(new OptInPlugin(address(whoRegistry), address(whereRegistry))));

        assertEq(plugin.WHERE_REGISTRY(), address(whereRegistry));
        assertEq(plugin.isOptedIn(alice, alice), false);
        assertEq(plugin.lastOptOut(alice, alice), 0);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        address who = alice;
        address where = bob;

        vm.startPrank(who);
        whoRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(who);
        plugin.optIn(where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(who, where), true);
        assertEq(plugin.lastOptOut(who, where), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(plugin.isOptedIn(who, where), true);
        assertEq(plugin.lastOptOut(who, where), 0);

        vm.startPrank(who);
        plugin.optOut(where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(who, where), false);
        assertEq(plugin.lastOptOut(who, where), blockTimestamp);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(plugin.isOptedIn(who, where), false);
        assertEq(plugin.lastOptOut(who, where), blockTimestamp - 1);

        vm.startPrank(who);
        plugin.optIn(where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(who, where), true);
        assertEq(plugin.lastOptOut(who, where), blockTimestamp - 1);

        vm.startPrank(who);
        plugin.optOut(where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(who, where), false);
        assertEq(plugin.lastOptOut(who, where), blockTimestamp);
    }

    function test_OptInRevertNotEntity() public {
        plugin = IOptInPlugin(address(new OptInPlugin(address(whoRegistry), address(whereRegistry))));

        address who = alice;
        address where = bob;

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(who);
        vm.expectRevert(IPlugin.NotEntity.selector);
        plugin.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertNotWhereEntity() public {
        plugin = IOptInPlugin(address(new OptInPlugin(address(whoRegistry), address(whereRegistry))));

        address who = alice;
        address where = bob;

        vm.startPrank(who);
        whoRegistry.register();
        vm.stopPrank();

        vm.startPrank(who);
        vm.expectRevert(IOptInPlugin.NotWhereEntity.selector);
        plugin.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertAlreadyOptedIn() public {
        plugin = IOptInPlugin(address(new OptInPlugin(address(whoRegistry), address(whereRegistry))));

        address who = alice;
        address where = bob;

        vm.startPrank(who);
        whoRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(who);
        plugin.optIn(where);
        vm.stopPrank();

        vm.startPrank(who);
        vm.expectRevert(IOptInPlugin.AlreadyOptedIn.selector);
        plugin.optIn(where);
        vm.stopPrank();
    }

    function test_OptOutRevertNotOptedIn() public {
        plugin = IOptInPlugin(address(new OptInPlugin(address(whoRegistry), address(whereRegistry))));

        address who = alice;
        address where = bob;

        vm.startPrank(who);
        whoRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(who);
        vm.expectRevert(IOptInPlugin.NotOptedIn.selector);
        plugin.optOut(where);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";

import {OperatorOptInPlugin} from "src/contracts/OperatorOptInPlugin.sol";
import {IOperatorOptInPlugin} from "src/interfaces/IOperatorOptInPlugin.sol";

contract OptInPluginTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry operatorRegistry;
    NonMigratablesRegistry whereRegistry;

    IOperatorOptInPlugin plugin;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        operatorRegistry = new NonMigratablesRegistry();
        whereRegistry = new NonMigratablesRegistry();
    }

    function test_Create() public {
        plugin =
            IOperatorOptInPlugin(address(new OperatorOptInPlugin(address(operatorRegistry), address(whereRegistry))));

        assertEq(plugin.WHERE_REGISTRY(), address(whereRegistry));
        assertEq(plugin.isOptedIn(alice, alice), false);
        assertEq(plugin.lastOptOut(alice, alice), 0);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        plugin.optIn(where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(operator, where), true);
        assertEq(plugin.lastOptOut(operator, where), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(plugin.isOptedIn(operator, where), true);
        assertEq(plugin.lastOptOut(operator, where), 0);

        vm.startPrank(operator);
        plugin.optOut(where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(operator, where), false);
        assertEq(plugin.lastOptOut(operator, where), blockTimestamp);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(plugin.isOptedIn(operator, where), false);
        assertEq(plugin.lastOptOut(operator, where), blockTimestamp - 1);

        vm.startPrank(operator);
        plugin.optIn(where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(operator, where), true);
        assertEq(plugin.lastOptOut(operator, where), blockTimestamp - 1);

        vm.startPrank(operator);
        plugin.optOut(where);
        vm.stopPrank();

        assertEq(plugin.isOptedIn(operator, where), false);
        assertEq(plugin.lastOptOut(operator, where), blockTimestamp);
    }

    function test_OptInRevertNotEntity() public {
        plugin =
            IOperatorOptInPlugin(address(new OperatorOptInPlugin(address(operatorRegistry), address(whereRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOperatorOptInPlugin.NotOperator.selector);
        plugin.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertNotWhereEntity() public {
        plugin =
            IOperatorOptInPlugin(address(new OperatorOptInPlugin(address(operatorRegistry), address(whereRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOperatorOptInPlugin.NotWhereEntity.selector);
        plugin.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertAlreadyOptedIn() public {
        plugin =
            IOperatorOptInPlugin(address(new OperatorOptInPlugin(address(operatorRegistry), address(whereRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        plugin.optIn(where);
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOperatorOptInPlugin.AlreadyOptedIn.selector);
        plugin.optIn(where);
        vm.stopPrank();
    }

    function test_OptOutRevertNotOptedIn() public {
        plugin =
            IOperatorOptInPlugin(address(new OperatorOptInPlugin(address(operatorRegistry), address(whereRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOperatorOptInPlugin.NotOptedIn.selector);
        plugin.optOut(where);
        vm.stopPrank();
    }
}

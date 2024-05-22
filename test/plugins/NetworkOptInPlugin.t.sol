// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {IPlugin} from "src/interfaces/base/IPlugin.sol";

import {NetworkOptInPlugin} from "src/contracts/plugins/NetworkOptInPlugin.sol";
import {INetworkOptInPlugin} from "src/interfaces/plugins/INetworkOptInPlugin.sol";

contract NetworkOptInPluginTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry operatorRegistry;
    NonMigratablesRegistry networkRegistry;

    INetworkOptInPlugin plugin;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        operatorRegistry = new NonMigratablesRegistry();
        networkRegistry = new NonMigratablesRegistry();
    }

    function test_Create() public {
        plugin =
            INetworkOptInPlugin(address(new NetworkOptInPlugin(address(operatorRegistry), address(networkRegistry))));

        assertEq(plugin.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(plugin.isOperatorOptedIn(alice, alice), false);
        assertEq(plugin.lastOperatorOptOut(alice, alice), 0);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        address operator = alice;
        address network = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        plugin.optIn(network);
        vm.stopPrank();

        assertEq(plugin.isOperatorOptedIn(operator, network), true);
        assertEq(plugin.lastOperatorOptOut(operator, network), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(plugin.isOperatorOptedIn(operator, network), true);
        assertEq(plugin.lastOperatorOptOut(operator, network), 0);

        vm.startPrank(operator);
        plugin.optOut(network);
        vm.stopPrank();

        assertEq(plugin.isOperatorOptedIn(operator, network), false);
        assertEq(plugin.lastOperatorOptOut(operator, network), blockTimestamp);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(plugin.isOperatorOptedIn(operator, network), false);
        assertEq(plugin.lastOperatorOptOut(operator, network), blockTimestamp - 1);

        vm.startPrank(operator);
        plugin.optIn(network);
        vm.stopPrank();

        assertEq(plugin.isOperatorOptedIn(operator, network), true);
        assertEq(plugin.lastOperatorOptOut(operator, network), blockTimestamp - 1);

        vm.startPrank(operator);
        plugin.optOut(network);
        vm.stopPrank();

        assertEq(plugin.isOperatorOptedIn(operator, network), false);
        assertEq(plugin.lastOperatorOptOut(operator, network), blockTimestamp);
    }

    function test_OptInRevertNotEntity() public {
        plugin =
            INetworkOptInPlugin(address(new NetworkOptInPlugin(address(operatorRegistry), address(networkRegistry))));

        address operator = alice;
        address network = bob;

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IPlugin.NotEntity.selector);
        plugin.optIn(network);
        vm.stopPrank();
    }

    function test_OptInRevertNotNetwork() public {
        plugin =
            INetworkOptInPlugin(address(new NetworkOptInPlugin(address(operatorRegistry), address(networkRegistry))));

        address operator = alice;
        address network = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(INetworkOptInPlugin.NotNetwork.selector);
        plugin.optIn(network);
        vm.stopPrank();
    }

    function test_OptInRevertOperatorAlreadyOptedIn() public {
        plugin =
            INetworkOptInPlugin(address(new NetworkOptInPlugin(address(operatorRegistry), address(networkRegistry))));

        address operator = alice;
        address network = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        plugin.optIn(network);
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(INetworkOptInPlugin.OperatorAlreadyOptedIn.selector);
        plugin.optIn(network);
        vm.stopPrank();
    }

    function test_OptOutRevertOperatorNotOptedIn() public {
        plugin =
            INetworkOptInPlugin(address(new NetworkOptInPlugin(address(operatorRegistry), address(networkRegistry))));

        address operator = alice;
        address network = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(INetworkOptInPlugin.OperatorNotOptedIn.selector);
        plugin.optOut(network);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";

import {NetworkOptInService} from "src/contracts/NetworkOptInService.sol";
import {INetworkOptInService} from "src/interfaces/INetworkOptInService.sol";

contract OptInServiceTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry networkRegistry;
    NonMigratablesRegistry whereRegistry;

    INetworkOptInService service;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        networkRegistry = new NonMigratablesRegistry();
        whereRegistry = new NonMigratablesRegistry();
    }

    function test_Create(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(whereRegistry))));

        assertEq(service.WHERE_REGISTRY(), address(whereRegistry));
        assertEq(service.isOptedIn(alice, alice, alice), false);
        assertEq(service.lastOptOut(alice, alice, alice), 0);

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
        service.optIn(resolver, where);
        vm.stopPrank();

        assertEq(service.isOptedIn(network, resolver, where), true);
        assertEq(service.lastOptOut(network, resolver, where), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(network, resolver, where), true);
        assertEq(service.lastOptOut(network, resolver, where), 0);

        vm.startPrank(network);
        service.optOut(resolver, where);
        vm.stopPrank();

        assertEq(service.isOptedIn(network, resolver, where), false);
        assertEq(service.lastOptOut(network, resolver, where), blockTimestamp);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(network, resolver, where), false);
        assertEq(service.lastOptOut(network, resolver, where), blockTimestamp - 1);

        vm.startPrank(network);
        service.optIn(resolver, where);
        vm.stopPrank();

        assertEq(service.isOptedIn(network, resolver, where), true);
        assertEq(service.lastOptOut(network, resolver, where), blockTimestamp - 1);

        vm.startPrank(network);
        service.optOut(resolver, where);
        vm.stopPrank();

        assertEq(service.isOptedIn(network, resolver, where), false);
        assertEq(service.lastOptOut(network, resolver, where), blockTimestamp);
    }

    function test_OptInRevertNotEntity(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(whereRegistry))));

        address network = alice;
        address where = bob;

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInService.NotNetwork.selector);
        service.optIn(resolver, where);
        vm.stopPrank();
    }

    function test_OptInRevertNotWhereEntity(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(whereRegistry))));

        address network = alice;
        address where = bob;

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInService.NotWhereEntity.selector);
        service.optIn(resolver, where);
        vm.stopPrank();
    }

    function test_OptInRevertAlreadyOptedIn(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(whereRegistry))));

        address network = alice;
        address where = bob;

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        service.optIn(resolver, where);
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInService.AlreadyOptedIn.selector);
        service.optIn(resolver, where);
        vm.stopPrank();
    }

    function test_OptOutRevertNotOptedIn(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(whereRegistry))));

        address network = alice;
        address where = bob;

        vm.startPrank(network);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInService.NotOptedIn.selector);
        service.optOut(resolver, where);
        vm.stopPrank();
    }
}

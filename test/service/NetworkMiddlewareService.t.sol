// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";

import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {INetworkMiddlewareService} from "../../src/interfaces/service/INetworkMiddlewareService.sol";

contract MiddlewareServiceTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NetworkRegistry registry;

    INetworkMiddlewareService service;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        registry = new NetworkRegistry();
    }

    function test_Create(
        address middleware
    ) public {
        vm.assume(middleware != address(0));

        service = INetworkMiddlewareService(address(new NetworkMiddlewareService(address(registry))));

        assertEq(service.NETWORK_REGISTRY(), address(registry));
        assertEq(service.middleware(alice), address(0));

        vm.startPrank(alice);
        registry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(alice);
        service.setMiddleware(middleware);
        vm.stopPrank();

        assertEq(service.middleware(alice), middleware);
    }

    function test_SetMiddlewareRevertNotNetwork(
        address middleware
    ) public {
        vm.assume(middleware != address(0));

        service = INetworkMiddlewareService(address(new NetworkMiddlewareService(address(registry))));

        vm.startPrank(alice);
        vm.expectRevert(INetworkMiddlewareService.NotNetwork.selector);
        service.setMiddleware(middleware);
        vm.stopPrank();
    }

    function test_SetMiddlewareRevertAlreadySet(
        address middleware
    ) public {
        vm.assume(middleware != address(0));

        service = INetworkMiddlewareService(address(new NetworkMiddlewareService(address(registry))));

        vm.startPrank(alice);
        registry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(alice);
        service.setMiddleware(middleware);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(INetworkMiddlewareService.AlreadySet.selector);
        service.setMiddleware(middleware);
        vm.stopPrank();
    }
}

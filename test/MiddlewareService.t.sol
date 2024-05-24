// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";

import {MiddlewareService} from "src/contracts/MiddlewareService.sol";
import {IMiddlewareService} from "src/interfaces/IMiddlewareService.sol";

contract MiddlewareServiceTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry registry;

    IMiddlewareService service;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        registry = new NonMigratablesRegistry();
    }

    function test_Create(address middleware) public {
        vm.assume(middleware != address(0));

        service = IMiddlewareService(address(new MiddlewareService(address(registry))));

        assertEq(service.middleware(alice), address(0));

        vm.startPrank(alice);
        registry.register();
        vm.stopPrank();

        vm.startPrank(alice);
        service.setMiddleware(middleware);
        vm.stopPrank();

        assertEq(service.middleware(alice), middleware);
    }

    function test_SetMiddlewareRevertNotEntity(address middleware) public {
        vm.assume(middleware != address(0));

        service = IMiddlewareService(address(new MiddlewareService(address(registry))));

        vm.startPrank(alice);
        vm.expectRevert(IMiddlewareService.NotEntity.selector);
        service.setMiddleware(middleware);
        vm.stopPrank();
    }

    function test_SetMiddlewareRevertAlreadySet(address middleware) public {
        vm.assume(middleware != address(0));

        service = IMiddlewareService(address(new MiddlewareService(address(registry))));

        vm.startPrank(alice);
        registry.register();
        vm.stopPrank();

        vm.startPrank(alice);
        service.setMiddleware(middleware);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMiddlewareService.AlreadySet.selector);
        service.setMiddleware(middleware);
        vm.stopPrank();
    }
}

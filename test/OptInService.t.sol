// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";

import {OptInService} from "src/contracts/OptInService.sol";
import {IOptInService} from "src/interfaces/IOptInService.sol";

contract OperatorOptInServiceTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    OperatorRegistry operatorRegistry;
    NetworkRegistry networkRegistry;

    IOptInService service;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        operatorRegistry = new OperatorRegistry();
        networkRegistry = new NetworkRegistry();
    }

    function test_Create() public {
        service = IOptInService(address(new OptInService(address(operatorRegistry), address(networkRegistry))));

        assertEq(service.WHERE_REGISTRY(), address(networkRegistry));
        assertEq(service.isOptedIn(alice, alice), false);
        assertEq(service.lastOptOut(alice, alice), 0);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), true);
        assertEq(service.lastOptOut(operator, where), 0);
        assertEq(service.wasOptedInAfter(operator, where, uint48(blockTimestamp)), true);
        assertEq(service.wasOptedInAfter(operator, where, uint48(blockTimestamp + 1)), true);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(operator, where), true);
        assertEq(service.lastOptOut(operator, where), 0);
        assertEq(service.wasOptedInAfter(operator, where, uint48(blockTimestamp)), true);

        vm.startPrank(operator);
        service.optOut(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), false);
        assertEq(service.lastOptOut(operator, where), blockTimestamp);
        assertEq(service.wasOptedInAfter(operator, where, uint48(blockTimestamp - 1)), true);
        assertEq(service.wasOptedInAfter(operator, where, uint48(blockTimestamp)), true);
        assertEq(service.wasOptedInAfter(operator, where, uint48(blockTimestamp + 1)), false);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(operator, where), false);
        assertEq(service.lastOptOut(operator, where), blockTimestamp - 1);

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), true);
        assertEq(service.lastOptOut(operator, where), blockTimestamp - 1);

        vm.startPrank(operator);
        service.optOut(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), false);
        assertEq(service.lastOptOut(operator, where), blockTimestamp);
    }

    function test_OptInRevertNotEntity() public {
        service = IOptInService(address(new OptInService(address(operatorRegistry), address(networkRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.NotWho.selector);
        service.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertNotWhereEntity() public {
        service = IOptInService(address(new OptInService(address(operatorRegistry), address(networkRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.NotWhereEntity.selector);
        service.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertAlreadyOptedIn() public {
        service = IOptInService(address(new OptInService(address(operatorRegistry), address(networkRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.AlreadyOptedIn.selector);
        service.optIn(where);
        vm.stopPrank();
    }

    function test_OptOutRevertNotOptedIn() public {
        service = IOptInService(address(new OptInService(address(operatorRegistry), address(networkRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();

        vm.startPrank(where);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.NotOptedIn.selector);
        service.optOut(where);
        vm.stopPrank();
    }
}

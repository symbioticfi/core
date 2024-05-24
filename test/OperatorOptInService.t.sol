// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";

import {OperatorOptInService} from "src/contracts/OperatorOptInService.sol";
import {IOperatorOptInService} from "src/interfaces/IOperatorOptInService.sol";

contract OperatorOptInServiceTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    OperatorRegistry operatorRegistry;
    NonMigratablesRegistry whereRegistry;

    IOperatorOptInService service;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        operatorRegistry = new OperatorRegistry();
        whereRegistry = new NonMigratablesRegistry();
    }

    function test_Create() public {
        service =
            IOperatorOptInService(address(new OperatorOptInService(address(operatorRegistry), address(whereRegistry))));

        assertEq(service.WHERE_REGISTRY(), address(whereRegistry));
        assertEq(service.isOptedIn(alice, alice), false);
        assertEq(service.lastOptOut(alice, alice), 0);

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
        service.optIn(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), true);
        assertEq(service.lastOptOut(operator, where), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(operator, where), true);
        assertEq(service.lastOptOut(operator, where), 0);

        vm.startPrank(operator);
        service.optOut(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), false);
        assertEq(service.lastOptOut(operator, where), blockTimestamp);

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
        service =
            IOperatorOptInService(address(new OperatorOptInService(address(operatorRegistry), address(whereRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOperatorOptInService.NotOperator.selector);
        service.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertNotWhereEntity() public {
        service =
            IOperatorOptInService(address(new OperatorOptInService(address(operatorRegistry), address(whereRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOperatorOptInService.NotWhereEntity.selector);
        service.optIn(where);
        vm.stopPrank();
    }

    function test_OptInRevertAlreadyOptedIn() public {
        service =
            IOperatorOptInService(address(new OperatorOptInService(address(operatorRegistry), address(whereRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOperatorOptInService.AlreadyOptedIn.selector);
        service.optIn(where);
        vm.stopPrank();
    }

    function test_OptOutRevertNotOptedIn() public {
        service =
            IOperatorOptInService(address(new OperatorOptInService(address(operatorRegistry), address(whereRegistry))));

        address operator = alice;
        address where = bob;

        vm.startPrank(operator);
        operatorRegistry.register();
        vm.stopPrank();

        vm.startPrank(where);
        whereRegistry.register();
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectRevert(IOperatorOptInService.NotOptedIn.selector);
        service.optOut(where);
        vm.stopPrank();
    }
}

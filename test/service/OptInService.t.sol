// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";

import {OptInService} from "src/contracts/service/OptInService.sol";
import {IOptInService} from "src/interfaces/service/IOptInService.sol";

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
        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        service = IOptInService(address(new OptInService(address(operatorRegistry), address(networkRegistry))));

        assertEq(service.WHERE_REGISTRY(), address(networkRegistry));
        assertEq(service.isOptedInAt(alice, alice, 0), false);
        assertEq(service.isOptedIn(alice, alice), false);

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

        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp - 1)), false);
        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp)), true);
        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp + 1)), true);
        assertEq(service.isOptedIn(operator, where), true);
        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp + 1), 0), true);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(operator, where), true);

        vm.startPrank(operator);
        service.optOut(where);
        vm.stopPrank();

        assertEq(service.isOptedInAt(operator, where, uint48(blockTimestamp - 1)), true);
        assertEq(service.isOptedIn(operator, where), false);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(operator, where), false);

        vm.startPrank(operator);
        service.optIn(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), true);

        vm.startPrank(operator);
        vm.expectRevert(IOptInService.OptOutCooldown.selector);
        service.optOut(where);
        vm.stopPrank();

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.startPrank(operator);
        service.optOut(where);
        vm.stopPrank();

        assertEq(service.isOptedIn(operator, where), false);
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

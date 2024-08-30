// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {OperatorRegistry} from "../src/contracts/OperatorRegistry.sol";
import {IOperatorRegistry} from "../src/interfaces/IOperatorRegistry.sol";

contract OperatorRegistryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    IOperatorRegistry registry;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
    }

    function test_Create() public {
        registry = new OperatorRegistry();

        assertEq(registry.isEntity(alice), false);
    }

    function test_Register() public {
        registry = new OperatorRegistry();

        vm.startPrank(alice);
        registry.registerOperator();
        vm.stopPrank();

        assertEq(registry.isEntity(alice), true);
    }

    function test_RegisterRevertEntityAlreadyRegistered() public {
        registry = new OperatorRegistry();

        vm.startPrank(alice);
        registry.registerOperator();
        vm.stopPrank();

        vm.expectRevert(IOperatorRegistry.OperatorAlreadyRegistered.selector);
        vm.startPrank(alice);
        registry.registerOperator();
        vm.stopPrank();
    }
}

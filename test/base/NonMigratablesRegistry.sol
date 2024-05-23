// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {INonMigratablesRegistry} from "src/interfaces/base/INonMigratablesRegistry.sol";

contract NonMigratablesRegistryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    INonMigratablesRegistry registry;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
    }

    function test_Create() public {
        registry = new NonMigratablesRegistry();

        assertEq(registry.isEntity(alice), false);
    }

    function test_Register() public {
        registry = new NonMigratablesRegistry();

        vm.startPrank(alice);
        registry.register();
        vm.stopPrank();

        assertEq(registry.isEntity(alice), true);
    }

    function test_RegisterRevertEntityAlreadyRegistered() public {
        registry = new NonMigratablesRegistry();

        vm.startPrank(alice);
        registry.register();
        vm.stopPrank();

        vm.expectRevert(INonMigratablesRegistry.EntityAlreadyRegistered.selector);
        vm.startPrank(alice);
        registry.register();
        vm.stopPrank();
    }
}

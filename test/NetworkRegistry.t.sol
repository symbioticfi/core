// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NetworkRegistry} from "../src/contracts/NetworkRegistry.sol";
import {INetworkRegistry} from "../src/interfaces/INetworkRegistry.sol";

contract NetworkRegistryTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    INetworkRegistry registry;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
    }

    function test_Create() public {
        registry = new NetworkRegistry();

        assertEq(registry.isEntity(alice), false);
    }

    function test_Register() public {
        registry = new NetworkRegistry();

        vm.startPrank(alice);
        registry.registerNetwork();
        vm.stopPrank();

        assertEq(registry.isEntity(alice), true);
    }

    function test_RegisterRevertEntityAlreadyRegistered() public {
        registry = new NetworkRegistry();

        vm.startPrank(alice);
        registry.registerNetwork();
        vm.stopPrank();

        vm.expectRevert(INetworkRegistry.NetworkAlreadyRegistered.selector);
        vm.startPrank(alice);
        registry.registerNetwork();
        vm.stopPrank();
    }
}

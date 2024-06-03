// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {SimpleRegistry} from "./mocks/SimpleRegistry.sol";

import {NetworkOptInService} from "src/contracts/NetworkOptInService.sol";
import {INetworkOptInService} from "src/interfaces/INetworkOptInService.sol";

contract NetworkOptInServiceTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NetworkRegistry networkRegistry;
    SimpleRegistry vaultRegistry;

    INetworkOptInService service;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        networkRegistry = new NetworkRegistry();
        vaultRegistry = new SimpleRegistry();
    }

    function test_Create(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(vaultRegistry))));

        assertEq(service.VAULT_REGISTRY(), address(vaultRegistry));
        assertEq(service.isOptedIn(alice, alice, alice), false);
        assertEq(service.lastOptOut(alice, alice, alice), 0);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;
        address network = alice;
        address vault = bob;

        vm.startPrank(network);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(vault);
        vaultRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        service.optIn(resolver, vault);
        vm.stopPrank();

        assertEq(service.isOptedIn(network, resolver, vault), true);
        assertEq(service.lastOptOut(network, resolver, vault), 0);
        assertEq(service.wasOptedInAfter(network, resolver, vault, uint48(blockTimestamp)), true);
        assertEq(service.wasOptedInAfter(network, resolver, vault, uint48(blockTimestamp + 1)), true);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(network, resolver, vault), true);
        assertEq(service.lastOptOut(network, resolver, vault), 0);
        assertEq(service.wasOptedInAfter(network, resolver, vault, uint48(blockTimestamp)), true);

        vm.startPrank(network);
        service.optOut(resolver, vault);
        vm.stopPrank();

        assertEq(service.isOptedIn(network, resolver, vault), false);
        assertEq(service.lastOptOut(network, resolver, vault), blockTimestamp);
        assertEq(service.wasOptedInAfter(network, resolver, vault, uint48(blockTimestamp - 1)), true);
        assertEq(service.wasOptedInAfter(network, resolver, vault, uint48(blockTimestamp)), true);
        assertEq(service.wasOptedInAfter(network, resolver, vault, uint48(blockTimestamp + 1)), false);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(service.isOptedIn(network, resolver, vault), false);
        assertEq(service.lastOptOut(network, resolver, vault), blockTimestamp - 1);

        vm.startPrank(network);
        service.optIn(resolver, vault);
        vm.stopPrank();

        assertEq(service.isOptedIn(network, resolver, vault), true);
        assertEq(service.lastOptOut(network, resolver, vault), blockTimestamp - 1);

        vm.startPrank(network);
        service.optOut(resolver, vault);
        vm.stopPrank();

        assertEq(service.isOptedIn(network, resolver, vault), false);
        assertEq(service.lastOptOut(network, resolver, vault), blockTimestamp);
    }

    function test_OptInRevertNotEntity(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(vaultRegistry))));

        address network = alice;
        address vault = bob;

        vm.startPrank(vault);
        vaultRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInService.NotNetwork.selector);
        service.optIn(resolver, vault);
        vm.stopPrank();
    }

    function test_OptInRevertNotVault(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(vaultRegistry))));

        address network = alice;
        address vault = bob;

        vm.startPrank(network);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInService.NotVault.selector);
        service.optIn(resolver, vault);
        vm.stopPrank();
    }

    function test_OptInRevertAlreadyOptedIn(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(vaultRegistry))));

        address network = alice;
        address vault = bob;

        vm.startPrank(network);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(vault);
        vaultRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        service.optIn(resolver, vault);
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInService.AlreadyOptedIn.selector);
        service.optIn(resolver, vault);
        vm.stopPrank();
    }

    function test_OptOutRevertNotOptedIn(address resolver) public {
        service =
            INetworkOptInService(address(new NetworkOptInService(address(networkRegistry), address(vaultRegistry))));

        address network = alice;
        address vault = bob;

        vm.startPrank(network);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(vault);
        vaultRegistry.register();
        vm.stopPrank();

        vm.startPrank(network);
        vm.expectRevert(INetworkOptInService.NotOptedIn.selector);
        service.optOut(resolver, vault);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterRegistry} from "../src/contracts/AdapterRegistry.sol";
import {IAdapterRegistry} from "../src/interfaces/IAdapterRegistry.sol";

contract AdapterRegistryTest is Test {
    AdapterRegistry internal registry;
    address internal owner;
    address internal alice;
    address internal vault;
    address internal otherVault;
    address internal adapter;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        vault = makeAddr("vault");
        otherVault = makeAddr("otherVault");
        adapter = makeAddr("adapter");
        registry = new AdapterRegistry(owner);
    }

    function test_SetGlobalWhitelistStatus() public {
        vm.prank(owner);
        registry.setGlobalWhitelistStatus(adapter, true);

        assertTrue(registry.globalIsWhitelisted(adapter));
        assertFalse(registry.vaultIsWhitelisted(vault, adapter));
        assertTrue(registry.isWhitelisted(vault, adapter));
        assertTrue(registry.isWhitelisted(otherVault, adapter));

        vm.prank(owner);
        registry.setGlobalWhitelistStatus(adapter, false);

        assertFalse(registry.globalIsWhitelisted(adapter));
        assertFalse(registry.isWhitelisted(vault, adapter));
        assertFalse(registry.isWhitelisted(otherVault, adapter));
    }

    function test_SetVaultWhitelistStatus() public {
        vm.prank(owner);
        registry.setVaultWhitelistStatus(vault, adapter, true);

        assertFalse(registry.globalIsWhitelisted(adapter));
        assertTrue(registry.vaultIsWhitelisted(vault, adapter));
        assertTrue(registry.isWhitelisted(vault, adapter));
        assertFalse(registry.isWhitelisted(otherVault, adapter));

        vm.prank(owner);
        registry.setVaultWhitelistStatus(vault, adapter, false);

        assertFalse(registry.vaultIsWhitelisted(vault, adapter));
        assertFalse(registry.isWhitelisted(vault, adapter));
    }

    function test_SetVaultWhitelistStatusCanBeRepeated() public {
        vm.startPrank(owner);
        registry.setVaultWhitelistStatus(vault, adapter, true);
        registry.setVaultWhitelistStatus(vault, adapter, true);
        vm.stopPrank();

        assertTrue(registry.isWhitelisted(vault, adapter));
    }

    function test_SetGlobalAndVaultWhitelistStatusRevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.setVaultWhitelistStatus(vault, adapter, true);

        vm.prank(alice);
        vm.expectRevert();
        registry.setGlobalWhitelistStatus(adapter, true);
    }

    function test_RemovedUpgradeableAndOldWhitelistApi() public {
        (bool initializeSuccess,) = address(registry).call(abi.encodeWithSignature("initialize(address)", owner));
        assertFalse(initializeSuccess);

        (bool whitelistSuccess,) =
            address(registry).call(abi.encodeWithSignature("whitelist(address,address)", address(0xBEEF), adapter));
        assertFalse(whitelistSuccess);

        (bool oldSetSuccess,) =
            address(registry).call(abi.encodeWithSignature("setWhitelistStatus(address,bool)", adapter, true));
        assertFalse(oldSetSuccess);

        (bool oldScopedSetSuccess,) = address(registry)
            .call(abi.encodeWithSignature("setWhitelistStatus(address,address,bool)", vault, adapter, true));
        assertFalse(oldScopedSetSuccess);

        assertEq(
            IAdapterRegistry.setGlobalWhitelistStatus.selector,
            bytes4(keccak256("setGlobalWhitelistStatus(address,bool)"))
        );
        assertEq(
            IAdapterRegistry.setVaultWhitelistStatus.selector,
            bytes4(keccak256("setVaultWhitelistStatus(address,address,bool)"))
        );
        assertEq(IAdapterRegistry.globalIsWhitelisted.selector, bytes4(keccak256("globalIsWhitelisted(address)")));
        assertEq(IAdapterRegistry.vaultIsWhitelisted.selector, bytes4(keccak256("vaultIsWhitelisted(address,address)")));
        assertEq(IAdapterRegistry.isWhitelisted.selector, bytes4(keccak256("isWhitelisted(address,address)")));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {AdapterRegistry} from "../src/contracts/AdapterRegistry.sol";
import {IAdapterRegistry} from "../src/interfaces/IAdapterRegistry.sol";

contract AdapterRegistryTest is Test {
    AdapterRegistry internal registry;
    address internal owner;
    address internal alice;
    address internal vault;
    address internal adapter;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        vault = makeAddr("vault");
        adapter = makeAddr("adapter");
        registry = new AdapterRegistry(owner);
    }

    function test_SetWhitelistedStatus() public {
        vm.prank(owner);
        registry.setWhitelistedStatus(vault, adapter, true);

        assertTrue(registry.isWhitelisted(vault, adapter));

        vm.prank(owner);
        registry.setWhitelistedStatus(vault, adapter, false);

        assertFalse(registry.isWhitelisted(vault, adapter));
    }

    function test_SetWhitelistedStatusCanBeRepeated() public {
        vm.startPrank(owner);
        registry.setWhitelistedStatus(vault, adapter, true);
        registry.setWhitelistedStatus(vault, adapter, true);
        vm.stopPrank();

        assertTrue(registry.isWhitelisted(vault, adapter));
    }

    function test_SetWhitelistedStatusRevertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.setWhitelistedStatus(vault, adapter, true);
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

        (bool oldGlobalSetSuccess,) =
            address(registry).call(abi.encodeWithSignature("setGlobalWhitelistStatus(address,bool)", adapter, true));
        assertFalse(oldGlobalSetSuccess);

        (bool oldVaultSetSuccess,) = address(registry)
            .call(abi.encodeWithSignature("setVaultWhitelistStatus(address,address,bool)", vault, adapter, true));
        assertFalse(oldVaultSetSuccess);

        assertEq(
            IAdapterRegistry.setWhitelistedStatus.selector,
            bytes4(keccak256("setWhitelistedStatus(address,address,bool)"))
        );
        assertEq(IAdapterRegistry.isWhitelisted.selector, bytes4(keccak256("isWhitelisted(address,address)")));
    }
}

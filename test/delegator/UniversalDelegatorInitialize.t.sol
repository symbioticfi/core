// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {
    IUniversalDelegator,
    UNIVERSAL_DELEGATOR_VERSION,
    FORCE_DEALLOCATE_ROLE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract UniversalDelegatorInitializeVaultMock {}

contract UniversalDelegatorInitializeTest is Test {
    using Clones for address;

    function testInitializeStartsWithoutAdapters() public {
        UniversalDelegatorInitializeVaultMock vault = new UniversalDelegatorInitializeVaultMock();
        UniversalDelegator delegator = _delegator();

        delegator.initialize(UNIVERSAL_DELEGATOR_VERSION, address(vault), _initData());

        assertEq(delegator.vault(), address(vault));
        assertEq(delegator.totalAdapters(), 0);
        assertEq(delegator.hasRole(FORCE_DEALLOCATE_ROLE, address(this)), true);
    }

    function testInitializeUsesOwnerAsVaultWithoutRegistryOrVersionChecks() public {
        UniversalDelegatorInitializeVaultMock vault = new UniversalDelegatorInitializeVaultMock();
        UniversalDelegator delegator = _delegator();

        delegator.initialize(UNIVERSAL_DELEGATOR_VERSION, address(vault), _initData());

        assertEq(delegator.vault(), address(vault));
    }

    function _delegator() internal returns (UniversalDelegator) {
        UniversalDelegator implementation = new UniversalDelegator(address(this), address(0), address(this));
        return UniversalDelegator(address(implementation).clone());
    }

    function _initData() internal view returns (bytes memory) {
        return abi.encode(
            IUniversalDelegator.InitParams({
                allocateRoleHolder: address(this),
                deallocateRoleHolder: address(this),
                addAdapterRoleHolder: address(this),
                swapAdaptersRoleHolder: address(this),
                defaultAdminRoleHolder: address(this),
                removeAdapterRoleHolder: address(this),
                forceDeallocateRoleHolder: address(this),
                setAdapterLimitsRoleHolder: address(this),
                setAutoAllocateAdaptersRoleHolder: address(this)
            })
        );
    }
}

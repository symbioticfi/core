// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {IUniversalDelegator, UNIVERSAL_DELEGATOR_TYPE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {VAULT_V2_VERSION} from "../../src/interfaces/vault/IVaultV2.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract UniversalDelegatorInitializeRegistryMock {
    mapping(address entity => bool status) public isEntity;

    function setEntity(address entity, bool status) external {
        isEntity[entity] = status;
    }
}

contract UniversalDelegatorInitializeVaultMock {
    function version() external pure returns (uint64) {
        return VAULT_V2_VERSION;
    }
}

contract UniversalDelegatorInitializeTest is Test {
    using Clones for address;

    function testInitializeStartsWithoutAdapters() public {
        UniversalDelegatorInitializeRegistryMock vaultFactory = new UniversalDelegatorInitializeRegistryMock();
        UniversalDelegatorInitializeVaultMock vault = new UniversalDelegatorInitializeVaultMock();

        vaultFactory.setEntity(address(vault), true);

        UniversalDelegator implementation =
            new UniversalDelegator(UNIVERSAL_DELEGATOR_TYPE, address(vaultFactory), address(0), address(this));
        UniversalDelegator delegator = UniversalDelegator(address(implementation).clone());

        delegator.initialize(
            abi.encode(
                address(vault),
                abi.encode(
                    IUniversalDelegator.InitParams({
                        allocateRoleHolder: address(this),
                        deallocateRoleHolder: address(this),
                        addAdapterRoleHolder: address(this),
                        swapAdaptersRoleHolder: address(this),
                        defaultAdminRoleHolder: address(this),
                        removeAdapterRoleHolder: address(this),
                        setAdapterLimitsRoleHolder: address(this),
                        setAutoAllocateAdaptersRoleHolder: address(this)
                    })
                )
            )
        );

        assertEq(delegator.vault(), address(vault));
        assertEq(delegator.totalAdapters(), 0);
    }
}

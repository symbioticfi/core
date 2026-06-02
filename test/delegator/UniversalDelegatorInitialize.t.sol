// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

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

contract UniversalDelegatorInitializeOldVaultMock {
    function version() external pure returns (uint64) {
        return VAULT_V2_VERSION - 1;
    }
}

contract UniversalDelegatorInitializeTest is Test {
    using Clones for address;

    function testInitializeStartsWithoutAdapters() public {
        UniversalDelegatorInitializeRegistryMock vaultFactory = new UniversalDelegatorInitializeRegistryMock();
        UniversalDelegatorInitializeVaultMock vault = new UniversalDelegatorInitializeVaultMock();

        vaultFactory.setEntity(address(vault), true);

        UniversalDelegator delegator = _delegator(vaultFactory);

        delegator.initialize(_initData(address(vault)));

        assertEq(delegator.vault(), address(vault));
        assertEq(delegator.totalAdapters(), 0);
    }

    function testInitializeRejectsUnregisteredVault() public {
        UniversalDelegatorInitializeRegistryMock vaultFactory = new UniversalDelegatorInitializeRegistryMock();
        UniversalDelegatorInitializeVaultMock vault = new UniversalDelegatorInitializeVaultMock();
        UniversalDelegator delegator = _delegator(vaultFactory);

        vm.expectRevert(IUniversalDelegator.NotVault.selector);
        delegator.initialize(_initData(address(vault)));
    }

    function testInitializeRejectsOldVault() public {
        UniversalDelegatorInitializeRegistryMock vaultFactory = new UniversalDelegatorInitializeRegistryMock();
        UniversalDelegatorInitializeOldVaultMock vault = new UniversalDelegatorInitializeOldVaultMock();
        UniversalDelegator delegator = _delegator(vaultFactory);

        vaultFactory.setEntity(address(vault), true);

        vm.expectRevert(IUniversalDelegator.OldVault.selector);
        delegator.initialize(_initData(address(vault)));
    }

    function _delegator(UniversalDelegatorInitializeRegistryMock vaultFactory) internal returns (UniversalDelegator) {
        UniversalDelegator implementation =
            new UniversalDelegator(UNIVERSAL_DELEGATOR_TYPE, address(vaultFactory), address(0), address(this));
        return UniversalDelegator(address(implementation).clone());
    }

    function _initData(address vault) internal view returns (bytes memory) {
        return abi.encode(
            vault,
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
        );
    }
}

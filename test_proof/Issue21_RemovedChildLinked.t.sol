// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {UniversalDelegator} from "../src/contracts/delegator/UniversalDelegator.sol";
import {
    IUniversalDelegator,
    CREATE_SLOT_ROLE,
    REMOVE_SLOT_ROLE,
    WITHDRAWAL_BUFFER_CHILD_INDEX
} from "../src/interfaces/delegator/IUniversalDelegator.sol";
import {IEntity} from "../src/interfaces/common/IEntity.sol";
import {IRegistry} from "../src/interfaces/common/IRegistry.sol";
import {VAULT_V2_VERSION} from "../src/interfaces/vault/IVaultV2.sol";
import {MigratableEntityProxy} from "../src/contracts/common/MigratableEntityProxy.sol";
import {UniversalDelegatorIndex} from "../src/contracts/libraries/UniversalDelegatorIndex.sol";
import {Subnetwork} from "../src/contracts/libraries/Subnetwork.sol";

contract MockRegistry is IRegistry {
    mapping(address entity => bool isEntity_) internal _isEntity;

    function setEntity(address entityAddr, bool isEntity_) external {
        _isEntity[entityAddr] = isEntity_;
    }

    function isEntity(address account) external view returns (bool) {
        return _isEntity[account];
    }

    function totalEntities() external pure returns (uint256) {
        return 0;
    }

    function entity(uint256) external pure returns (address) {
        return address(0);
    }
}

contract MockVaultV2 {
    uint48 internal immutable _epochDuration;
    uint256 internal _activeStake;
    uint256 internal _allocatable;

    constructor(uint48 epochDuration_, uint256 activeStake_, uint256 allocatable_) {
        _epochDuration = epochDuration_;
        _activeStake = activeStake_;
        _allocatable = allocatable_;
    }

    function version() external pure returns (uint64) {
        return VAULT_V2_VERSION;
    }

    function epochDuration() external view returns (uint48) {
        return _epochDuration;
    }

    function activeStake() external view returns (uint256) {
        return _activeStake;
    }

    function activeWithdrawalsFor(uint48) external pure returns (uint256) {
        return 0;
    }

    function allocatable() external view returns (uint256) {
        return _allocatable;
    }
}

contract Issue21_RemovedChildLinked_Test is Test {
    using UniversalDelegatorIndex for uint96;

    MockRegistry internal vaultFactory;
    MockRegistry internal networkRegistry;
    MockVaultV2 internal vault;
    UniversalDelegator internal delegator;

    function setUp() public {
        vaultFactory = new MockRegistry();
        networkRegistry = new MockRegistry();

        vault = new MockVaultV2({
            epochDuration_: 100,
            activeStake_: 1e18,
            allocatable_: 1e18
        });
        vaultFactory.setEntity(address(vault), true);

        UniversalDelegator implementation = new UniversalDelegator({
            networkRegistry: address(networkRegistry),
            vaultFactory: address(vaultFactory),
            delegatorFactory: address(this),
            entityType: 4,
            networkMiddlewareService: address(0)
        });

        IUniversalDelegator.InitParams memory params = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: address(this),
            hook: address(0),
            hookSetRoleHolder: address(0),
            createSlotRoleHolder: address(this),
            setSizeRoleHolder: address(0),
            swapSlotsRoleHolder: address(0),
            withdrawalBufferSize: 0
        });

        bytes memory initData = abi.encode(address(vault), abi.encode(params));
        MigratableEntityProxy proxy = new MigratableEntityProxy(
            address(implementation), abi.encodeCall(IEntity.initialize, (initData))
        );
        delegator = UniversalDelegator(address(proxy));

        // `REMOVE_SLOT_ROLE` is not assigned via init params in the current implementation.
        delegator.grantRole(REMOVE_SLOT_ROLE, address(this));
    }

    function _assertNoInactiveChildReachable(uint96 parentIndex) internal view {
        IUniversalDelegator.Slot memory parentSlot = delegator.getSlot(parentIndex);

        uint32 childIndex = parentSlot.firstChild;
        if (parentIndex == 0) {
            while (childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX) {
                uint96 childSlotIndex = parentIndex.createIndex(childIndex);
                IUniversalDelegator.Slot memory childSlot = delegator.getSlot(childSlotIndex);
                assertTrue(childSlot.exists, "reachable child is inactive");
                childIndex = childSlot.nextSlot;
            }
        } else {
            while (childIndex > 0) {
                uint96 childSlotIndex = parentIndex.createIndex(childIndex);
                IUniversalDelegator.Slot memory childSlot = delegator.getSlot(childSlotIndex);
                assertTrue(childSlot.exists, "reachable child is inactive");
                childIndex = childSlot.nextSlot;
            }
        }
    }

    function test_Issue21_removeSlot_doesNotLeaveInactiveChildReachable() public {
        uint96 sv = delegator.createSlot(bytes32(0), 0, false, false, 0);

        bytes32 s1 = Subnetwork.subnetwork(address(0xBEEF1), 1);
        bytes32 s2 = Subnetwork.subnetwork(address(0xBEEF2), 1);

        uint96 n1 = delegator.createSlot(s1, sv, false, false, 0);
        delegator.createSlot(s2, sv, false, false, 0);

        delegator.removeSlot(n1);

        _assertNoInactiveChildReachable(sv);
        _assertNoInactiveChildReachable(0);
    }

    function test_Issue21_resetAllocation_doesNotLeaveInactiveChildReachable() public {
        address network1 = address(0xBEEF1);
        address network2 = address(0xBEEF2);
        networkRegistry.setEntity(network1, true);
        networkRegistry.setEntity(network2, true);

        uint96 sv = delegator.createSlot(bytes32(0), 0, false, false, 0);

        bytes32 s1 = Subnetwork.subnetwork(network1, 1);
        bytes32 s2 = Subnetwork.subnetwork(network2, 1);

        delegator.createSlot(s1, sv, false, false, 0);
        delegator.createSlot(s2, sv, false, false, 0);

        vm.prank(network1);
        delegator.resetAllocation(s1);

        _assertNoInactiveChildReachable(sv);
        _assertNoInactiveChildReachable(0);
    }
}

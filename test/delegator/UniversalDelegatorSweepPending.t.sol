// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {
    IUniversalDelegator,
    UNIVERSAL_DELEGATOR_TYPE,
    REMOVE_ADAPTER_ROLE,
    SET_ADAPTER_LIMITS_ROLE,
    SET_AUTO_ALLOCATE_ADAPTERS_ROLE,
    SWAP_ADAPTERS_ROLE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

contract UniversalDelegatorSweepHarness is UniversalDelegator {
    constructor(address adapterRegistry)
        UniversalDelegator(UNIVERSAL_DELEGATOR_TYPE, address(0x1), adapterRegistry, address(0x3))
    {}

    function setVault(address vault_) external {
        vault = vault_;
    }

    function addAdapterForTest(address adapter) external returns (uint16) {
        return _addAdapter(adapter);
    }

    function grantRoleForTest(bytes32 role, address account) external {
        _grantRole(role, account);
    }
}

contract UniversalDelegatorAdapterFactoryMock {
    mapping(address entity => bool status) public isEntity;

    function setEntity(address entity, bool status) external {
        isEntity[entity] = status;
    }
}

contract UniversalDelegatorAdapterRegistryMock {
    mapping(address delegator => mapping(address adapterFactory => bool status)) public isWhitelisted;

    function setWhitelisted(address delegator, address adapterFactory, bool status) external {
        isWhitelisted[delegator][adapterFactory] = status;
    }
}

contract UniversalDelegatorSweepQueue {
    uint256 public pendingAssets;
    uint256 public pendingAfterFill;
    uint256 public fillCalls;

    constructor(uint256 pendingAssets_) {
        pendingAssets = pendingAssets_;
    }

    function setPendingAfterFill(uint256 pendingAfterFill_) external {
        pendingAfterFill = pendingAfterFill_;
    }

    function fill() external {
        ++fillCalls;
        pendingAssets = pendingAfterFill;
    }
}

contract UniversalDelegatorSweepVault {
    address public withdrawalQueue;
    uint256 public pushedAssets;
    address public lastPushAdapter;

    constructor(address withdrawalQueue_) {
        withdrawalQueue = withdrawalQueue_;
    }

    function push(uint256 assets, address adapter) external {
        pushedAssets += assets;
        lastPushAdapter = adapter;
    }
}

contract UniversalDelegatorSweepAdapter {
    address public immutable FACTORY;
    uint256 public totalAssets;
    uint256 public deallocateReturn;
    uint256 public lastDeallocateAmount;
    uint256 public lastRequestDeallocateAmount;
    uint256 public requestDeallocateCalls;

    constructor(address factory, uint256 totalAssets_, uint256 deallocateReturn_) {
        FACTORY = factory;
        totalAssets = totalAssets_;
        deallocateReturn = deallocateReturn_;
    }

    function allocatable() external pure returns (uint256) {
        return 0;
    }

    function deallocatable() external view returns (uint256) {
        return totalAssets;
    }

    function allocate(uint256) external pure returns (uint256) {
        return 0;
    }

    function deallocate(uint256 amount) external returns (uint256 deallocated) {
        lastDeallocateAmount = amount;
        deallocated = deallocateReturn > amount ? amount : deallocateReturn;
        totalAssets -= deallocated;
    }

    function requestDeallocate(uint256 amount) external {
        lastRequestDeallocateAmount = amount;
        ++requestDeallocateCalls;
    }
}

contract UniversalDelegatorSweepPendingTest is Test {
    UniversalDelegatorAdapterFactoryMock internal adapterFactory;
    UniversalDelegatorAdapterRegistryMock internal adapterRegistry;
    UniversalDelegatorSweepHarness internal delegator;

    function setUp() public {
        adapterFactory = new UniversalDelegatorAdapterFactoryMock();
        adapterRegistry = new UniversalDelegatorAdapterRegistryMock();
        delegator = new UniversalDelegatorSweepHarness(address(adapterRegistry));
        adapterRegistry.setWhitelisted(address(delegator), address(adapterFactory), true);
    }

    function _newAdapter(uint256 totalAssets, uint256 deallocateReturn)
        internal
        returns (UniversalDelegatorSweepAdapter adapter)
    {
        adapter = new UniversalDelegatorSweepAdapter(address(adapterFactory), totalAssets, deallocateReturn);
        adapterFactory.setEntity(address(adapter), true);
    }

    function test_AddAdapterAddsToDeallocationRouteAndReusesStableIndex() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 0);

        uint16 firstIndex = delegator.addAdapterForTest(address(adapter));

        assertEq(firstIndex, 1);
        assertEq(delegator.totalAdapters(), 1);
        assertEq(delegator.adapterToIndex(address(adapter)), 1);
        assertEq(delegator.indexToAdapter(1), address(adapter));
        assertEq(delegator.adapters(0), address(adapter));

        delegator.grantRoleForTest(REMOVE_ADAPTER_ROLE, address(this));
        delegator.removeAdapter(address(adapter));

        uint16 secondIndex = delegator.addAdapterForTest(address(adapter));

        assertEq(secondIndex, firstIndex);
        assertEq(delegator.totalAdapters(), 1);
        assertEq(delegator.adapters(0), address(adapter));
    }

    function test_SwapAdaptersSwapsAdaptersInRoute() public {
        UniversalDelegatorSweepAdapter adapter1 = _newAdapter(100, 0);
        UniversalDelegatorSweepAdapter adapter2 = _newAdapter(100, 0);
        UniversalDelegatorSweepAdapter adapter3 = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter1));
        delegator.addAdapterForTest(address(adapter2));
        delegator.addAdapterForTest(address(adapter3));
        delegator.grantRoleForTest(SWAP_ADAPTERS_ROLE, address(this));

        delegator.swapAdapters(address(adapter1), address(adapter3));

        assertEq(delegator.adapters(0), address(adapter3));
        assertEq(delegator.adapters(1), address(adapter2));
        assertEq(delegator.adapters(2), address(adapter1));
    }

    function test_SetAutoAllocateAdaptersRevertsIfAdapterIsNotInAdapters() public {
        UniversalDelegatorSweepAdapter adapter1 = _newAdapter(100, 0);
        UniversalDelegatorSweepAdapter adapter2 = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter1));
        delegator.grantRoleForTest(SET_AUTO_ALLOCATE_ADAPTERS_ROLE, address(this));

        address[] memory route = new address[](1);
        route[0] = address(adapter1);
        delegator.setAutoAllocateAdapters(route);
        assertEq(delegator.autoAllocateAdapters(0), address(adapter1));

        route[0] = address(adapter2);
        vm.expectRevert(IUniversalDelegator.InvalidAdapter.selector);
        delegator.setAutoAllocateAdapters(route);
    }

    function test_LimitsAreStoredByAdapterAddress() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(adapter), 123, 456);

        assertEq(delegator.absoluteLimitOf(address(adapter)), 123);
        assertEq(delegator.shareLimitOf(address(adapter)), 456);
    }

    function test_SweepPendingStoresPendingAdapterIndexes() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(100);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 0);
        queue.setPendingAfterFill(100);

        delegator.setVault(address(vault));
        uint16 index = delegator.addAdapterForTest(address(adapter));

        uint256 pendingAssets = delegator.sweepPending();

        assertEq(pendingAssets, 100);
        assertEq(adapter.lastRequestDeallocateAmount(), 100);
        assertEq(delegator.adaptersWithPending(0), index);
    }

    function test_SweepPendingDoesNotRequestStalePendingAfterFill() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(100);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 60);

        delegator.setVault(address(vault));
        delegator.addAdapterForTest(address(adapter));

        uint256 pendingAssets = delegator.sweepPending();

        assertEq(pendingAssets, 0);
        assertEq(queue.fillCalls(), 1);
        assertEq(vault.pushedAssets(), 60);
        assertEq(vault.lastPushAdapter(), address(adapter));
        assertEq(adapter.lastDeallocateAmount(), 100);
        assertEq(adapter.requestDeallocateCalls(), 0);
        assertEq(adapter.lastRequestDeallocateAmount(), 0);
    }
}

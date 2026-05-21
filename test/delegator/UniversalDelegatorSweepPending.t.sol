// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

contract UniversalDelegatorSweepHarness is UniversalDelegator {
    constructor() UniversalDelegator(UNIVERSAL_DELEGATOR_TYPE, address(0x1), address(0x2), address(0x3)) {}

    function setVault(address vault_) external {
        vault = vault_;
    }

    function addAdapterForTest(address adapter) external {
        adapters.push(adapter);
        uint8 index = uint8(adapters.length);
        adapterIndex[adapter] = index;
        adaptersToDeallocate.push(index);
    }
}

contract UniversalDelegatorSweepQueue {
    uint256 public pendingAssets;
    uint256 public fillCalls;

    constructor(uint256 pendingAssets_) {
        pendingAssets = pendingAssets_;
    }

    function fill() external {
        ++fillCalls;
        pendingAssets = 0;
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
    uint256 public totalAssets;
    uint256 public deallocateReturn;
    uint256 public lastDeallocateAmount;
    uint256 public lastRequestDeallocateAmount;
    uint256 public requestDeallocateCalls;

    constructor(uint256 totalAssets_, uint256 deallocateReturn_) {
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
    function test_SweepPendingDoesNotRequestStalePendingAfterFill() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(100);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        UniversalDelegatorSweepAdapter adapter = new UniversalDelegatorSweepAdapter(100, 60);
        UniversalDelegatorSweepHarness delegator = new UniversalDelegatorSweepHarness();

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

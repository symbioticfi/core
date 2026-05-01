// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {FenwickTreeCheckpoints} from "../../src/contracts/libraries/FenwickTreeCheckpoints.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {
    CREATE_SLOT_ROLE,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

contract UniversalDelegatorFlatRegistryMock {
    function isEntity(address) external pure returns (bool) {
        return true;
    }
}

contract UniversalDelegatorFlatMiddlewareMock {
    mapping(address network => address middleware) public middleware;

    function setMiddleware(address network, address middleware_) external {
        middleware[network] = middleware_;
    }
}

contract UniversalDelegatorFlatVaultMock {
    uint48 public epochDuration = 10;
    uint256 public activeStake;
    address public slasher;

    function setActiveStake(uint256 activeStake_) external {
        activeStake = activeStake_;
    }

    function setSlasher(address slasher_) external {
        slasher = slasher_;
    }

    function activeStakeAt(uint48, bytes calldata) external view returns (uint256) {
        return activeStake;
    }

    function activeWithdrawalsFor(uint48) external pure returns (uint256) {
        return 0;
    }

    function activeWithdrawalsForAt(uint48, uint48) external pure returns (uint256) {
        return 0;
    }
}

contract UniversalDelegatorFlatLegacyMock {
    uint256 public stakeAtValue;

    function setStakeAtValue(uint256 value) external {
        stakeAtValue = value;
    }

    function stakeAt(bytes32, address, uint48, bytes calldata) external view returns (uint256) {
        return stakeAtValue;
    }
}

contract UniversalDelegatorFlatHarness is UniversalDelegator {
    using FenwickTreeCheckpoints for FenwickTreeCheckpoints.Tree;

    constructor(address registry, address middleware)
        UniversalDelegator(registry, address(0), address(0), 0, middleware)
    {}

    function initializeForTest(address vault_, address roleHolder) external {
        vault = vault_;
        _prevSums.initialize(1);
        _grantRole(CREATE_SLOT_ROLE, roleHolder);
        _grantRole(SET_SIZE_ROLE, roleHolder);
        _grantRole(REMOVE_SLOT_ROLE, roleHolder);
    }

    function setMigrationForTest(address oldDelegator_, uint48 migrateTimestamp_) external {
        oldDelegator = oldDelegator_;
        migrateTimestamp = migrateTimestamp_;
    }
}

contract UniversalDelegatorFlatCoverageTest is Test {
    using Subnetwork for address;

    UniversalDelegatorFlatRegistryMock internal registry;
    UniversalDelegatorFlatMiddlewareMock internal middlewareService;
    UniversalDelegatorFlatVaultMock internal vault;
    UniversalDelegatorFlatHarness internal delegator;

    address internal networkA = address(0x1001);
    address internal networkB = address(0x1002);
    address internal middlewareA = address(0x2001);
    address internal middlewareB = address(0x2002);
    address internal operatorA = address(0x3001);
    address internal operatorB = address(0x3002);

    function setUp() public {
        vm.warp(1);
        registry = new UniversalDelegatorFlatRegistryMock();
        middlewareService = new UniversalDelegatorFlatMiddlewareMock();
        vault = new UniversalDelegatorFlatVaultMock();
        delegator = new UniversalDelegatorFlatHarness(address(registry), address(middlewareService));
        delegator.initializeForTest(address(vault), address(this));

        middlewareService.setMiddleware(networkA, middlewareA);
        middlewareService.setMiddleware(networkB, middlewareB);
        vault.setActiveStake(1000);
    }

    function test_MaturedDecreaseKeepsLaterSlotUnusedUntilSync() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkB, operatorB, 100);

        assertEq(slotA, 1);
        assertEq(slotB, 2);
        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkB, operatorB), 0);

        delegator.setSize(slotA, 0);
        vm.warp(block.timestamp + vault.epochDuration());

        assertEq(delegator.getSize(slotA), 0);
        assertEq(delegator.stake(subnetworkB, operatorB), 0);
        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, uint48(block.timestamp)), 0);

        delegator.setSize(slotB, 100);

        assertEq(delegator.stake(subnetworkB, operatorB), 100);
        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, uint48(block.timestamp)), 100);
    }

    function test_DecreaseImmediatelyReleasesOnlyUnusedStakeAndDelaysAllocatedRemainder() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(40);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkB, operatorB, 100);

        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 40);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);

        delegator.setSize(slotA, 20);

        assertEq(delegator.getSize(slotA), 40);
        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 40);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);

        vm.warp(block.timestamp + vault.epochDuration());

        assertEq(delegator.getSize(slotA), 20);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);

        delegator.setSize(slotB, 100);

        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 20);
    }

    function test_ResetAfterMaturedDecreasePreservesOtherSlotHistoricalStake() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkB, operatorB, 100);
        delegator.setSize(slotA, 0);

        uint48 maturedAt = uint48(block.timestamp + vault.epochDuration());
        vm.warp(maturedAt);
        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, maturedAt), 0);

        vm.prank(middlewareA);
        delegator.resetAllocation(subnetworkA, operatorA);

        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, maturedAt), 100);
        assertEq(delegator.stake(subnetworkA, operatorA), 0);
    }

    function test_StakeForAtBeforeMigrationDoesNotSynthesizeLegacyStakeForAt() public {
        bytes32 subnetwork = networkA.subnetwork(0);
        UniversalDelegatorFlatLegacyMock legacy = new UniversalDelegatorFlatLegacyMock();
        legacy.setStakeAtValue(77);
        delegator.setMigrationForTest(address(legacy), 50);

        assertEq(delegator.stakeAt(subnetwork, operatorA, 49, ""), 77);
        assertEq(delegator.stakeForAt(subnetwork, operatorA, vault.epochDuration() - 1, 49), 0);
    }

    function test_NetworkOperatorPairsAreFullyIsolated() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);

        uint32 slotA1 = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotA2 = delegator.createSlot(subnetworkA, operatorB, 200);
        uint32 slotB1 = delegator.createSlot(subnetworkB, operatorA, 300);

        assertEq(delegator.getSlotOf(subnetworkA, operatorA), slotA1);
        assertEq(delegator.getSlotOf(subnetworkA, operatorB), slotA2);
        assertEq(delegator.getSlotOf(subnetworkB, operatorA), slotB1);
        assertEq(delegator.getSlotOf(subnetworkB, operatorB), 0);
        assertEq(delegator.stake(subnetworkB, operatorB), 0);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);
        assertEq(delegator.stakeAt(subnetworkB, operatorB, uint48(block.timestamp), ""), 0);
        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, uint48(block.timestamp)), 0);
    }

    function test_ResetAllocationDropsOnlyTargetPair() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(200);

        delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkA, operatorB, 100);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 100);

        vm.prank(middlewareA);
        delegator.resetAllocation(subnetworkA, operatorA);

        assertEq(delegator.stake(subnetworkA, operatorA), 0);
        assertEq(delegator.stake(subnetworkA, operatorB), 100);
    }

    function test_RemoveMiddleSlotReleasesPrefixForLaterSlot() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        bytes32 subnetworkC = address(0x1003).subnetwork(0);
        address operatorC = address(0x3003);
        vault.setActiveStake(100);

        delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkB, operatorB, 100);
        delegator.createSlot(subnetworkC, operatorC, 100);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkB, operatorB), 0);
        assertEq(delegator.stake(subnetworkC, operatorC), 0);

        delegator.removeSlot(slotB);
        vault.setActiveStake(200);

        assertEq(delegator.stake(subnetworkB, operatorB), 0);
        assertEq(delegator.stake(subnetworkC, operatorC), 100);
    }

    function test_LastLiveSlotCanGrowBeyondWithdrawalBuffer() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 50);

        delegator.setSize(slotA, 101);

        assertEq(delegator.getSize(slotA), 101);
        assertEq(delegator.stake(subnetworkA, operatorA), 100);
    }

    function test_EarlierSlotCannotGrowByStealingLaterAllocation() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(150);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkA, operatorB, 100);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 50);

        vm.expectRevert(IUniversalDelegator.NotEnoughBalance.selector);
        delegator.setSize(slotA, 151);
    }
}

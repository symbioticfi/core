// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {console2} from "forge-std/console2.sol";

import {UniversalDelegatorCompactNewSimulationTest} from "./UniversalDelegatorCompactNewSimulation.t.sol";

import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {UniversalDelegatorCompactNew} from "./UniversalDelegatorCompactNew.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

import {ISlasher, SLASHER_TYPE} from "../../src/interfaces/slasher/ISlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalSlasher, UNIVERSAL_SLASHER_TYPE} from "../../src/interfaces/slasher/IUniversalSlasher.sol";

contract UniversalDelegatorCompactNewProofSearchTest is UniversalDelegatorCompactNewSimulationTest {
    using Subnetwork for address;

    uint256 internal constant SEEDS_NO_SLASH = 80;
    uint256 internal constant STEPS_NO_SLASH = 8;
    uint256 internal constant SEEDS_WITH_SLASH = 240;
    uint256 internal constant STEPS_WITH_SLASH = 12;

    uint48[] internal waits;
    address internal slasherAddress;
    IUniversalSlasher internal slasher;

    struct RefTriplet {
        uint256 stake0;
        uint256 stakeHalf;
        uint256 stakeMax;
    }

    struct SlashEffect {
        bool didSlash;
        uint256 slotIndex;
        uint256 slashAmount;
    }

    struct SharedOverCase {
        uint128 initialDeposit;
        uint128 withdrawal;
        uint128 downSize;
        uint128 laterDeposit;
        uint128 slashAmount;
        uint48 waitBeforeSlash;
        uint48 waitAfterSlash;
    }

    struct SharedOverState {
        address middleware;
        bytes32[4] subnetworks;
        address[6] operators;
        uint96[2] subvaults;
    }

    function test_searchReferenceDivergence_withoutSlash() public {
        _initWaits();
        bool found = _runSearch(false);
        assertTrue(found, "no divergence found without slash");
    }

    function test_searchReferenceSpace_withSlash() public {
        _initWaits();
        _installSlasher();
        bool found = _runSearch(true);
        assertFalse(found, "found divergence after slash in sampled space");
    }

    function test_searchSlashDoesNotReduceOwnStakeByMoreThanAmount() public {
        _initWaits();
        _installSlasher();
        bool found = _runSlashBoundSearch();
        assertFalse(found, "found slash reducing own stakeFor by more than slashed amount");
    }

    function test_searchSharedSubvaultFutureDepositDoesNotIncreaseAggregateSlashableStake() public {
        _installSlasher();

        uint256 snapshot = vm.snapshotState();
        for (uint256 seed = 1; seed <= 96; ++seed) {
            bool found = _runSharedOverSeed(seed);
            if (found) {
                fail("found shared overutilization witness");
            }
            vm.revertToState(snapshot);
            snapshot = vm.snapshotState();
        }
    }

    function test_seed3_slashOnlyReducesOwnStakeBySlashedAmount() public {
        _initWaits();
        _installSlasher();

        uint96[4] memory slots;
        uint128[4] memory sizes;
        address[4] memory operators;
        uint256 seed = 3;
        bytes32 subnetwork = _subnetwork(1000 + seed);
        (, uint96 network) = _createOperatorTree(1000 + seed);

        uint256 r0 = uint256(keccak256(abi.encode(seed, true, "init")));
        vm.warp(1000 + seed);
        _deposit(alice, (((r0 >> 8) % 241) + 180) * 1 ether);

        for (uint256 i = 0; i < 4; ++i) {
            operators[i] = address(uint160(uint256(keccak256(abi.encode(seed, "operator", i)))));
            sizes[i] = uint128((((r0 >> (32 + i * 32)) % 121) + 20) * 1 ether);
            slots[i] = _createOperatorSlot(network, operators[i], sizes[i]);
        }

        for (uint256 step = 0; step < 9; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step, true, "step")));
            _applyAction(r, true, subnetwork, slots, sizes, operators);
        }

        RefTriplet memory beforeSlash = _slotTriplet(slots[0]);

        uint256 rSlash = uint256(keccak256(abi.encode(seed, uint256(9), true, "step")));
        (, SlashEffect memory effect) = _applyAction(rSlash, true, subnetwork, slots, sizes, operators);
        assertTrue(effect.didSlash);
        assertEq(effect.slotIndex, 0);
        assertEq(effect.slashAmount, 15 ether);

        RefTriplet memory afterSlash = _slotTriplet(slots[0]);

        assertEq(beforeSlash.stake0 - afterSlash.stake0, 15 ether);
        assertEq(beforeSlash.stakeHalf - afterSlash.stakeHalf, 15 ether);
        assertEq(beforeSlash.stakeMax - afterSlash.stakeMax, 15 ether);
    }

    function test_sharedSubvaultNetworkSlash_propagatesToSubvaultAndSiblingPathForSlasher() public {
        _installSlasher();

        vm.warp(1);
        _deposit(alice, 20 ether);

        bytes32 networkA = bytes32(uint256(1));
        bytes32 networkB = bytes32(uint256(2));
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 10 ether);
        uint96 network1 = delegator.createSlot(networkA, subvault, false, false, 10 ether);
        uint96 operator1 = delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(networkB, subvault, false, false, 10 ether);
        uint96 operator2 = delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);

        vm.startPrank(slasherAddress);
        uint256 actualFirstSlash = delegator.onSlash(networkA, alice, 10 ether, "");
        VaultV2(address(vault)).onSlash(actualFirstSlash, false);
        assertEq(delegator.getAllocated(subvault, 0), 0);
        assertEq(delegator.getAllocated(network1, 0), 0);
        assertEq(delegator.getAllocated(network2, 0), 10 ether);
        assertEq(delegator.getAllocated(operator1, 0), 0);
        assertEq(delegator.getAllocated(operator2, 0), 10 ether);
        assertEq(delegator.stakeFor(networkA, alice, 0), 0);
        assertEq(delegator.stakeFor(networkB, bob, 0), 10 ether);
        vm.stopPrank();

        assertEq(actualFirstSlash, 10 ether);
        assertEq(delegator.getSlot(subvault).size, 0);
        assertEq(delegator.getSlot(subvault).sizeSlashedPendingCumulative, 10 ether);
        assertEq(delegator.getSlot(network1).size, 0);
        assertEq(delegator.getSlot(network1).sizeSlashedPendingCumulative, 10 ether);
        assertEq(delegator.getSlot(network2).sizeSlashedPendingCumulative, 0);
        assertEq(delegator.getSlot(operator1).size, 0);
        assertEq(delegator.getSlot(operator1).sizeSlashedPendingCumulative, 0);
        assertEq(delegator.getSlot(operator2).size, 10 ether);
        assertEq(vault.activeStake(), 10 ether);

        assertEq(delegator.getAllocated(subvault, 0), 0);
        assertEq(delegator.getAllocated(network1, 0), 0);
        assertEq(delegator.getAllocated(network2, 0), 0);
        assertEq(delegator.getAllocated(operator1, 0), 0);
        assertEq(delegator.getAllocated(operator2, 0), 0);
        assertEq(delegator.stakeFor(networkA, alice, 0), 0);
        assertEq(delegator.stakeFor(networkB, bob, 0), 0);
    }

    function test_sharedSubvaultNetworkSlash_makesChildVisibleAboveParentForSlasher() public {
        _installSlasher();

        vm.warp(6);
        _deposit(alice, 20 ether);

        bytes32 networkA = bytes32(uint256(1));
        bytes32 networkB = bytes32(uint256(2));
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 10 ether);
        uint96 network1 = delegator.createSlot(networkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(networkB, subvault, false, false, 10 ether);
        uint96 operator2 = delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);

        vm.startPrank(slasherAddress);
        uint256 actualSlash = delegator.onSlash(networkA, alice, 10 ether, "");
        VaultV2(address(vault)).onSlash(actualSlash, false);

        uint256 subvaultAlloc = delegator.getAllocated(subvault, 0);
        uint256 network2Alloc = delegator.getAllocated(network2, 0);
        uint256 operator2Alloc = delegator.getAllocated(operator2, 0);
        vm.stopPrank();

        assertEq(actualSlash, 10 ether);
        assertEq(subvaultAlloc, 0);
        assertEq(network2Alloc, 10 ether);
        assertEq(operator2Alloc, 10 ether);
        assertGt(network2Alloc, subvaultAlloc);
        assertGt(operator2Alloc, subvaultAlloc);
    }

    function test_sharedSubvaultNetworkSlash_viaUniversalSlasher_makesChildVisibleAboveParent() public {
        _installSlasher();

        address networkAAddr = makeAddr("shared-network-a");
        address networkBAddr = makeAddr("shared-network-b");
        address middleware = makeAddr("shared-middleware");
        _registerNetwork(networkAAddr, middleware);
        _registerNetwork(networkBAddr, middleware);

        vm.warp(7);
        _deposit(alice, 20 ether);

        bytes32 subnetworkA = networkAAddr.subnetwork(0);
        bytes32 subnetworkB = networkBAddr.subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 10 ether);
        uint96 network1 = delegator.createSlot(subnetworkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(subnetworkB, subvault, false, false, 10 ether);
        uint96 operator2 = delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);

        vm.startPrank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetworkA, alice, 10 ether, 0, "");
        uint256 actualSlash = slasher.executeSlash(slashIndex, "");
        vm.stopPrank();

        vm.startPrank(slasherAddress);
        uint256 subvaultAlloc = delegator.getAllocated(subvault, 0);
        uint256 network2Alloc = delegator.getAllocated(network2, 0);
        uint256 operator2Alloc = delegator.getAllocated(operator2, 0);
        vm.stopPrank();

        assertEq(actualSlash, 10 ether);
        assertEq(subvaultAlloc, 0);
        assertEq(network2Alloc, 10 ether);
        assertEq(operator2Alloc, 10 ether);
        assertGt(network2Alloc, subvaultAlloc);
        assertGt(operator2Alloc, subvaultAlloc);
    }

    function test_sharedSubvault_slashableStakePreservesSiblingGuaranteeBeyondCurrentSubvaultAllocation() public {
        _installSlasher();

        address networkAAddr = makeAddr("shared-network-a-2");
        address networkBAddr = makeAddr("shared-network-b-2");
        address middleware = makeAddr("shared-middleware-2");
        _registerNetwork(networkAAddr, middleware);
        _registerNetwork(networkBAddr, middleware);

        vm.warp(8);
        _deposit(alice, 20 ether);

        bytes32 subnetworkA = networkAAddr.subnetwork(0);
        bytes32 subnetworkB = networkBAddr.subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 10 ether);
        uint96 network1 = delegator.createSlot(subnetworkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(subnetworkB, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);

        vm.startPrank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetworkA, alice, 10 ether, 0, "");
        uint256 slash1 = slasher.executeSlash(slashIndex1, "");
        uint256 slashableB = slasher.slashableStake(subnetworkB, bob, 0, "");
        vm.stopPrank();

        vm.prank(slasherAddress);
        uint256 slasherStakeB = delegator.stakeFor(subnetworkB, bob, 0);

        assertEq(slash1, 10 ether);
        assertEq(delegator.getAllocated(subvault, 0), 0);
        assertEq(delegator.stakeFor(subnetworkA, alice, 0), 0);
        assertEq(delegator.stakeFor(subnetworkB, bob, 0), 0);
        assertEq(slasherStakeB, 10 ether);
        assertEq(slashableB, 10 ether);
        assertEq(vault.activeStake(), 10 ether);

        vm.startPrank(middleware);
        uint256 slashIndex2 = slasher.requestSlash(subnetworkB, bob, 10 ether, 0, "");
        assertEq(slashIndex2, 1);
        vm.stopPrank();
    }

    function test_sharedSubvault_futureDepositDoesNotIncreasePreservedSlashableStake() public {
        _installSlasher();

        address networkAAddr = makeAddr("shared-network-a-5");
        address networkBAddr = makeAddr("shared-network-b-5");
        address middleware = makeAddr("shared-middleware-5");
        _registerNetwork(networkAAddr, middleware);
        _registerNetwork(networkBAddr, middleware);

        vm.warp(10);
        _deposit(alice, 20 ether);

        bytes32 subnetworkA = networkAAddr.subnetwork(0);
        bytes32 subnetworkB = networkBAddr.subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 10 ether);
        uint96 network1 = delegator.createSlot(subnetworkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(subnetworkB, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);

        vm.startPrank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetworkA, alice, 10 ether, 0, "");
        uint256 slash1 = slasher.executeSlash(slashIndex1, "");
        vm.stopPrank();

        assertEq(slash1, 10 ether);
        assertEq(delegator.getAllocated(subvault, 0), 0);
        assertEq(slasher.slashableStake(subnetworkB, bob, 0, ""), 10 ether);

        _deposit(alice, 10 ether);

        assertEq(delegator.getAllocated(subvault, 0), 0);
        assertEq(slasher.slashableStake(subnetworkB, bob, 0, ""), 10 ether);
        assertEq(delegator.stakeFor(subnetworkA, alice, 0), 0);
        assertEq(delegator.stakeFor(subnetworkB, bob, 0), 0);
    }

    function test_sharedSubvault_pendingSlashPreservesSiblingGuaranteeUntilPendingExpiry() public {
        _installSlasher();

        address networkAAddr = makeAddr("shared-network-a-pending");
        address networkBAddr = makeAddr("shared-network-b-pending");
        address middleware = makeAddr("shared-middleware-pending");
        address charlie = makeAddr("charlie-pending");
        _registerNetwork(networkAAddr, middleware);
        _registerNetwork(networkBAddr, middleware);

        vm.warp(13);
        _deposit(alice, 20 ether);

        bytes32 subnetworkA = networkAAddr.subnetwork(0);
        bytes32 subnetworkB = networkBAddr.subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 20 ether);
        uint96 network1 = delegator.createSlot(subnetworkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(subnetworkB, subvault, false, false, 20 ether);
        delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(charlie))), network2, false, false, 10 ether);

        _withdraw(alice, 20 ether);
        delegator.setSize(subvault, 0);

        assertEq(slasher.slashableStake(subnetworkB, bob, 0, ""), 10 ether);
        assertEq(slasher.slashableStake(subnetworkB, charlie, 0, ""), 10 ether);

        vm.warp(block.timestamp + EPOCH_DURATION - 2);

        vm.startPrank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetworkA, alice, 10 ether, 0, "");
        uint256 actualSlash = slasher.executeSlash(slashIndex, "");
        vm.stopPrank();

        assertEq(actualSlash, 10 ether);
        assertEq(delegator.stakeFor(subnetworkB, bob, 0), 10 ether);
        assertEq(delegator.stakeFor(subnetworkB, charlie, 0), 0);
        assertEq(slasher.slashableStake(subnetworkB, bob, 0, ""), 10 ether);
        assertEq(slasher.slashableStake(subnetworkB, charlie, 0, ""), 10 ether);

        vm.warp(block.timestamp + 3);

        assertEq(slasher.slashableStake(subnetworkB, bob, 0, ""), 0);
        assertEq(slasher.slashableStake(subnetworkB, charlie, 0, ""), 0);
    }

    function test_sharedSubvault_freshNetworkInheritsOldSlashCreditAndOverstatesFreshOperatorSlashableStake() public {
        _installSlasher();

        address networkAAddr = makeAddr("shared-network-a-fresh");
        address networkBAddr = makeAddr("shared-network-b-fresh");
        address middleware = makeAddr("shared-middleware-fresh");
        address charlie = makeAddr("charlie-fresh");
        _registerNetwork(networkAAddr, middleware);
        _registerNetwork(networkBAddr, middleware);

        vm.warp(14);
        _deposit(alice, 100 ether);

        bytes32 subnetworkA = networkAAddr.subnetwork(0);
        bytes32 subnetworkB = networkBAddr.subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 100 ether);
        delegator.createSlot(
            bytes32(uint256(uint160(alice))),
            delegator.createSlot(subnetworkA, subvault, false, false, 100 ether),
            false,
            false,
            100 ether
        );

        vm.startPrank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetworkA, alice, 80 ether, 0, "");
        uint256 slash1 = slasher.executeSlash(slashIndex1, "");
        vm.stopPrank();

        assertEq(slash1, 80 ether);
        assertEq(vault.activeStake(), 20 ether);
        assertEq(delegator.stakeFor(subnetworkA, alice, 0), 20 ether);

        uint96 network2 = delegator.createSlot(subnetworkB, subvault, false, false, 0);
        delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 50 ether);
        uint96 operatorCharlie =
            delegator.createSlot(bytes32(uint256(uint160(charlie))), network2, false, false, 50 ether);

        assertEq(delegator.getAllocated(network2, 0), 0);
        assertEq(delegator.getAllocated(operatorCharlie, 0), 0);
        assertEq(delegator.stakeFor(subnetworkB, charlie, 0), 0);

        delegator.setSize(network2, 100 ether);

        assertEq(delegator.getAllocated(subvault, 0), 20 ether);
        assertEq(delegator.getAllocated(network2, 0), 20 ether);
        assertEq(delegator.getAllocated(operatorCharlie, 0), 0);
        assertEq(delegator.stakeFor(subnetworkB, charlie, 0), 0);

        uint256 slashableCharlie = slasher.slashableStake(subnetworkB, charlie, 0, "");
        assertEq(slashableCharlie, 50 ether);
        assertEq(delegator.stakeFor(subnetworkB, charlie, 0), 0);

        vm.startPrank(middleware);
        uint256 slashIndex2 = slasher.requestSlash(subnetworkB, charlie, slashableCharlie, 0, "");
        uint256 slash2 = slasher.executeSlash(slashIndex2, "");
        vm.stopPrank();

        assertEq(slash2, 20 ether);
        assertLt(slash2, slashableCharlie);
    }

    function test_sharedSubvault_futureDepositDoesNotDoubleCountAcrossMultipleSubvaults() public {
        _installSlasher();

        address middleware = makeAddr("shared-middleware-6");
        address[4] memory networks = [
            makeAddr("shared-network-a1-6"),
            makeAddr("shared-network-b1-6"),
            makeAddr("shared-network-a2-6"),
            makeAddr("shared-network-b2-6")
        ];
        for (uint256 i = 0; i < networks.length; ++i) {
            _registerNetwork(networks[i], middleware);
        }

        vm.warp(12);
        _deposit(alice, 40 ether);

        bytes32[4] memory subnetworks;
        subnetworks[0] = networks[0].subnetwork(0);
        subnetworks[1] = networks[1].subnetwork(0);
        subnetworks[2] = networks[2].subnetwork(0);
        subnetworks[3] = networks[3].subnetwork(0);

        address[4] memory operators = [alice, bob, makeAddr("carol-6"), makeAddr("dave-6")];
        uint96[2] memory subvaults;

        subvaults[0] = delegator.createSlot(bytes32(0), 0, true, false, 20 ether);
        uint96 networkSlot = delegator.createSlot(subnetworks[0], subvaults[0], false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(operators[0]))), networkSlot, false, false, 10 ether);
        networkSlot = delegator.createSlot(subnetworks[1], subvaults[0], false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(operators[1]))), networkSlot, false, false, 10 ether);

        subvaults[1] = delegator.createSlot(bytes32(0), 0, true, false, 20 ether);
        networkSlot = delegator.createSlot(subnetworks[2], subvaults[1], false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(operators[2]))), networkSlot, false, false, 10 ether);
        networkSlot = delegator.createSlot(subnetworks[3], subvaults[1], false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(operators[3]))), networkSlot, false, false, 10 ether);

        vm.startPrank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetworks[0], operators[0], 10 ether, 0, "");
        uint256 slashIndex2 = slasher.requestSlash(subnetworks[2], operators[2], 10 ether, 0, "");
        uint256 slash1 = slasher.executeSlash(slashIndex1, "");
        uint256 slash2 = slasher.executeSlash(slashIndex2, "");
        vm.stopPrank();

        assertEq(slash1, 10 ether);
        assertEq(slash2, 10 ether);

        uint256 slashableBeforeDepositB1 = slasher.slashableStake(subnetworks[1], operators[1], 0, "");
        uint256 slashableBeforeDepositB2 = slasher.slashableStake(subnetworks[3], operators[3], 0, "");
        uint256 currentSubvaultBeforeDeposit =
            delegator.getAllocated(subvaults[0], 0) + delegator.getAllocated(subvaults[1], 0);

        assertEq(slashableBeforeDepositB1, 10 ether);
        assertEq(slashableBeforeDepositB2, 10 ether);
        assertEq(currentSubvaultBeforeDeposit, 20 ether);
        assertLe(slashableBeforeDepositB1 + slashableBeforeDepositB2, currentSubvaultBeforeDeposit);

        _deposit(alice, 10 ether);

        uint256 slashableAfterDepositB1 = slasher.slashableStake(subnetworks[1], operators[1], 0, "");
        uint256 slashableAfterDepositB2 = slasher.slashableStake(subnetworks[3], operators[3], 0, "");
        uint256 currentSubvaultAfterDeposit =
            delegator.getAllocated(subvaults[0], 0) + delegator.getAllocated(subvaults[1], 0);

        assertEq(currentSubvaultAfterDeposit, currentSubvaultBeforeDeposit);
        assertEq(slashableAfterDepositB1, slashableBeforeDepositB1);
        assertEq(slashableAfterDepositB2, slashableBeforeDepositB2);
        assertLe(slashableAfterDepositB1 + slashableAfterDepositB2, currentSubvaultAfterDeposit);
        assertLe(slashableAfterDepositB1 + slashableAfterDepositB2, vault.activeStake() + vault.activeWithdrawalsFor(0));
    }

    function test_sharedSubvault_futureDepositDoesNotReviveOldPendingSlashAcrossMultipleSubvaults() public {
        _installSlasher();

        address middleware = makeAddr("shared-middleware-over");
        address[4] memory networks = [
            makeAddr("shared-network-a1-over"),
            makeAddr("shared-network-b1-over"),
            makeAddr("shared-network-a2-over"),
            makeAddr("shared-network-b2-over")
        ];
        for (uint256 i = 0; i < networks.length; ++i) {
            _registerNetwork(networks[i], middleware);
        }

        address[6] memory operators = [
            alice,
            makeAddr("bob-over"),
            makeAddr("charlie-over"),
            makeAddr("carol-over"),
            makeAddr("dave-over"),
            makeAddr("erin-over")
        ];

        bytes32[4] memory subnetworks;
        for (uint256 i = 0; i < subnetworks.length; ++i) {
            subnetworks[i] = networks[i].subnetwork(0);
        }

        vm.warp(60);
        _deposit(alice, 40 ether);

        uint96[2] memory subvaults;
        subvaults[0] = _createSharedSubvaultWithTwoNetworks(
            subnetworks[0], operators[0], subnetworks[1], operators[1], operators[2]
        );
        subvaults[1] = _createSharedSubvaultWithTwoNetworks(
            subnetworks[2], operators[3], subnetworks[3], operators[4], operators[5]
        );

        _withdraw(alice, 40 ether);
        delegator.setSize(subvaults[0], 10 ether);
        delegator.setSize(subvaults[1], 10 ether);

        vm.warp(block.timestamp + EPOCH_DURATION - 1);

        vm.startPrank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetworks[0], operators[0], 10 ether, 0, "");
        uint256 slashIndex2 = slasher.requestSlash(subnetworks[2], operators[3], 10 ether, 0, "");
        uint256 slash1 = slasher.executeSlash(slashIndex1, "");
        uint256 slash2 = slasher.executeSlash(slashIndex2, "");
        vm.stopPrank();

        assertEq(slash1, 10 ether);
        assertEq(slash2, 10 ether);
        assertEq(delegator.getSlot(subvaults[0]).size, 10 ether);
        assertEq(delegator.getSlot(subvaults[1]).size, 10 ether);
        assertEq(delegator.getSlot(subvaults[0]).sizeSlashedPendingCumulative, 0);
        assertEq(delegator.getSlot(subvaults[1]).sizeSlashedPendingCumulative, 0);

        vm.warp(block.timestamp + 2);

        assertEq(vault.activeStake(), 0);
        assertEq(vault.activeWithdrawalsFor(0), 0);
        assertEq(slasher.slashableStake(subnetworks[1], operators[1], 0, ""), 0);
        assertEq(slasher.slashableStake(subnetworks[1], operators[2], 0, ""), 0);
        assertEq(slasher.slashableStake(subnetworks[3], operators[4], 0, ""), 0);
        assertEq(slasher.slashableStake(subnetworks[3], operators[5], 0, ""), 0);

        _deposit(alice, 20 ether);

        _assertSharedSubvaultNoOverAfterFutureDeposit(subnetworks, operators, subvaults);
    }

    function test_sharedSubvault_firstSlash_preservesSiblingOperatorsSlashableStake_viaUniversalSlasher() public {
        _installSlasher();

        address networkAAddr = makeAddr("shared-network-a-3");
        address networkBAddr = makeAddr("shared-network-b-3");
        address middleware = makeAddr("shared-middleware-3");
        address charlie = makeAddr("charlie");
        _registerNetwork(networkAAddr, middleware);
        _registerNetwork(networkBAddr, middleware);

        vm.warp(9);
        _deposit(alice, 30 ether);

        bytes32 subnetworkA = networkAAddr.subnetwork(0);
        bytes32 subnetworkB = networkBAddr.subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 20 ether);
        uint96 network1 = delegator.createSlot(subnetworkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(subnetworkB, subvault, false, false, 20 ether);
        delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(charlie))), network2, false, false, 10 ether);

        assertEq(delegator.stakeFor(subnetworkA, alice, 0), 10 ether);
        assertEq(delegator.stakeFor(subnetworkB, bob, 0), 10 ether);
        assertEq(delegator.stakeFor(subnetworkB, charlie, 0), 10 ether);

        vm.startPrank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetworkA, alice, 10 ether, 0, "");
        uint256 slash1 = slasher.executeSlash(slashIndex1, "");
        uint256 slashableBob = slasher.slashableStake(subnetworkB, bob, 0, "");
        uint256 slashableCharlie = slasher.slashableStake(subnetworkB, charlie, 0, "");
        vm.stopPrank();

        assertEq(slash1, 10 ether);
        assertEq(delegator.stakeFor(subnetworkA, alice, 0), 0);
        assertEq(delegator.stakeFor(subnetworkB, bob, 0), 10 ether);
        assertEq(delegator.stakeFor(subnetworkB, charlie, 0), 0);

        vm.startPrank(slasherAddress);
        assertEq(delegator.stakeFor(subnetworkB, bob, 0), 10 ether);
        assertEq(delegator.stakeFor(subnetworkB, charlie, 0), 10 ether);
        vm.stopPrank();

        assertEq(slashableBob, 10 ether);
        assertEq(slashableCharlie, 10 ether);
    }

    function test_sharedSubvault_siblingRequestCanExpireBeforeItsOwnSlashWindowEnds() public {
        _installSlasher();

        address networkAAddr = makeAddr("shared-network-a-4");
        address networkBAddr = makeAddr("shared-network-b-4");
        address middleware = makeAddr("shared-middleware-4");
        address charlie = makeAddr("charlie-4");
        _registerNetwork(networkAAddr, middleware);
        _registerNetwork(networkBAddr, middleware);

        vm.warp(40);
        _deposit(alice, 30 ether);

        bytes32 subnetworkA = networkAAddr.subnetwork(0);
        bytes32 subnetworkB = networkBAddr.subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 20 ether);
        uint96 network1 = delegator.createSlot(subnetworkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(subnetworkB, subvault, false, false, 20 ether);
        delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(charlie))), network2, false, false, 10 ether);

        vm.startPrank(middleware);
        uint256 slashIndexA = slasher.requestSlash(subnetworkA, alice, 10 ether, 0, "");
        vm.warp(block.timestamp + 2);
        uint256 firstSlash = slasher.executeSlash(slashIndexA, "");
        vm.stopPrank();

        assertEq(firstSlash, 10 ether);
        assertEq(delegator.stakeFor(subnetworkB, charlie, 0), 0);

        vm.prank(slasherAddress);
        assertEq(delegator.stakeFor(subnetworkB, charlie, 0), 10 ether);

        vm.warp(block.timestamp + EPOCH_DURATION - 2);
        vm.prank(middleware);
        uint256 siblingRequest = slasher.requestSlash(subnetworkB, charlie, 10 ether, 0, "");
        uint48 siblingRequestTimestamp = uint48(block.timestamp);

        assertEq(slasher.slashableStake(subnetworkB, charlie, 0, ""), 10 ether);

        vm.warp(block.timestamp + 3);
        assertLt(uint256(siblingRequestTimestamp), block.timestamp);
        assertLt(block.timestamp - uint256(siblingRequestTimestamp), uint256(EPOCH_DURATION));
        assertEq(slasher.slashableStake(subnetworkB, charlie, siblingRequestTimestamp, ""), 0);

        vm.startPrank(middleware);
        vm.expectRevert(IUniversalSlasher.InsufficientSlash.selector);
        slasher.executeSlash(siblingRequest, "");
        vm.stopPrank();
    }

    function test_sharedSubvaultNetworkSlash_expiresAfterEpoch() public {
        _installSlasher();

        vm.warp(11);
        _deposit(alice, 20 ether);

        bytes32 networkA = bytes32(uint256(1));
        bytes32 networkB = bytes32(uint256(2));
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 10 ether);
        uint96 network1 = delegator.createSlot(networkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(networkB, subvault, false, false, 10 ether);
        uint96 operator2 = delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);

        vm.startPrank(slasherAddress);
        uint256 actualSlash = delegator.onSlash(networkA, alice, 10 ether, "");
        VaultV2(address(vault)).onSlash(actualSlash, false);
        assertEq(delegator.getAllocated(network2, 0), 10 ether);
        assertEq(delegator.getAllocated(operator2, 0), 10 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + EPOCH_DURATION + 1);

        vm.startPrank(slasherAddress);
        assertEq(delegator.getAllocated(subvault, 0), 0);
        assertEq(delegator.getAllocated(network2, 0), 0);
        assertEq(delegator.getAllocated(operator2, 0), 0);
        vm.stopPrank();
    }

    function test_sharedSubvaultNetworkSlash_nonSlasherCannotSeeSiblingPath() public {
        _installSlasher();

        vm.warp(21);
        _deposit(alice, 20 ether);

        bytes32 networkA = bytes32(uint256(1));
        bytes32 networkB = bytes32(uint256(2));
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 10 ether);
        uint96 network1 = delegator.createSlot(networkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(networkB, subvault, false, false, 10 ether);
        uint96 operator2 = delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);

        vm.startPrank(slasherAddress);
        uint256 actualSlash = delegator.onSlash(networkA, alice, 10 ether, "");
        VaultV2(address(vault)).onSlash(actualSlash, false);
        vm.stopPrank();

        assertEq(actualSlash, 10 ether);
        assertEq(vault.activeStake(), 10 ether);

        assertEq(delegator.getAllocated(subvault, 0), 0);
        assertEq(delegator.getAllocated(network1, 0), 0);
        assertEq(delegator.getAllocated(network2, 0), 0);
        assertEq(delegator.getAllocated(operator2, 0), 0);
        assertEq(delegator.stakeFor(networkB, bob, 0), 0);
    }

    function test_sharedSubvaultNetworkSlash_historicalReadMissesSlasherSiblingPath() public {
        _installSlasher();

        vm.warp(31);
        _deposit(alice, 20 ether);

        bytes32 networkA = bytes32(uint256(1));
        bytes32 networkB = bytes32(uint256(2));
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 10 ether);
        uint96 network1 = delegator.createSlot(networkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(alice))), network1, false, false, 10 ether);
        uint96 network2 = delegator.createSlot(networkB, subvault, false, false, 10 ether);
        uint96 operator2 = delegator.createSlot(bytes32(uint256(uint160(bob))), network2, false, false, 10 ether);

        vm.startPrank(slasherAddress);
        uint256 actualSlash = delegator.onSlash(networkA, alice, 10 ether, "");
        VaultV2(address(vault)).onSlash(actualSlash, false);
        uint48 slashTimestamp = uint48(block.timestamp);

        assertEq(delegator.getAllocated(network2, 0), 10 ether);
        assertEq(delegator.getAllocated(operator2, 0), 10 ether);
        assertEq(delegator.getAllocatedAt(network2, 0, slashTimestamp), 0);
        assertEq(delegator.getAllocatedAt(operator2, 0, slashTimestamp), 0);
        vm.stopPrank();
    }

    function test_seed35_referenceDivergenceTimeline() public {
        uint96[4] memory slots;
        uint128[4] memory sizes = [uint128(78 ether), uint128(40 ether), uint128(85 ether), uint128(137 ether)];
        address[4] memory operators = [
            0x8b581E7ae7367E10fde04495402dA7c768F32147,
            0x736a998058a97c024f43d4a1FEa198Bf4aDbf710,
            0x5d2fACc15de7fAfcE588FC31B911D165D41b8311,
            0x09B25566e19b2b929B96d5a0e777b0f9D1045C54
        ];
        (, uint96 network) = _createOperatorTree(4001);

        vm.warp(1035);
        _deposit(alice, 244 ether);

        for (uint256 i = 0; i < 4; ++i) {
            slots[i] = _createOperatorSlot(network, operators[i], sizes[i]);
        }

        _reportReferenceCheckpoint("seed35 t0: initial state", slots, sizes);

        _withdraw(alice, 73 ether);
        _withdraw(alice, 32 ether);
        delegator.setSize(slots[1], 4 ether);
        sizes[1] = 4 ether;
        _deposit(alice, 32 ether);

        _reportReferenceCheckpoint("seed35 t1: after withdraw, withdraw, downsize slot2, deposit", slots, sizes);

        vm.warp(block.timestamp + HALF_DURATION);

        _reportReferenceCheckpoint("seed35 t2: after half-duration warp", slots, sizes);

        RefTriplet[4] memory ref = _reference(slots, sizes);
        assertEq(delegator.getAllocated(slots[2], 0), 85 ether);
        assertEq(delegator.getAllocated(slots[2], HALF_DURATION), 53 ether);
        assertEq(delegator.getAllocated(slots[2], MAX_DURATION), 53 ether);
        assertEq(ref[2].stake0, 85 ether);
        assertEq(ref[2].stakeHalf, 85 ether);
        assertEq(ref[2].stakeMax, 85 ether);
    }

    function test_seed35_underallocatesAtHalfDurationEvenWithoutActiveWithdrawals() public {
        uint96[4] memory slots;
        uint128[4] memory sizes = [uint128(78 ether), uint128(40 ether), uint128(85 ether), uint128(137 ether)];
        address[4] memory operators = [
            0x8b581E7ae7367E10fde04495402dA7c768F32147,
            0x736a998058a97c024f43d4a1FEa198Bf4aDbf710,
            0x5d2fACc15de7fAfcE588FC31B911D165D41b8311,
            0x09B25566e19b2b929B96d5a0e777b0f9D1045C54
        ];
        (, uint96 network) = _createOperatorTree(4002);

        vm.warp(1035);
        _deposit(alice, 244 ether);

        for (uint256 i = 0; i < 4; ++i) {
            slots[i] = _createOperatorSlot(network, operators[i], sizes[i]);
        }

        _withdraw(alice, 73 ether);
        _withdraw(alice, 32 ether);
        delegator.setSize(slots[1], 4 ether);
        _deposit(alice, 32 ether);

        vm.warp(block.timestamp + HALF_DURATION);

        uint256 totalHalf = delegator.getAllocated(slots[0], HALF_DURATION)
            + delegator.getAllocated(slots[1], HALF_DURATION) + delegator.getAllocated(slots[2], HALF_DURATION)
            + delegator.getAllocated(slots[3], HALF_DURATION);

        assertEq(vault.activeWithdrawalsFor(HALF_DURATION), 0);
        assertEq(vault.activeStake(), 171 ether);
        assertEq(totalHalf, 135 ether);
    }

    function _initWaits() internal {
        if (waits.length > 0) {
            return;
        }
        waits.push(0);
        waits.push(1);
        waits.push(1 days);
        waits.push(HALF_DURATION);
        waits.push(2 days);
        waits.push(MAX_DURATION);
    }

    function _installSlasher() internal {
        if (slasherAddress != address(0)) {
            return;
        }

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);

        address universalSlasherImpl = address(
            new UniversalSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(universalSlasherImpl);

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: owner,
                vaultParams: abi.encode(
                    IVaultV2.InitParams({
                        name: "Compact Vault Slash",
                        symbol: "CVLTS",
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: EPOCH_DURATION,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0),
                        setPluginLimitRoleHolder: address(0),
                        allocatePluginRoleHolder: address(0)
                    })
                ),
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: abi.encode(
                    UniversalDelegatorCompactNew.InitParams({
                        defaultAdminRoleHolder: owner, createSlotRoleHolder: owner, setSizeRoleHolder: owner
                    })
                ),
                withSlasher: true,
                slasherIndex: uint64(UNIVERSAL_SLASHER_TYPE),
                slasherParams: abi.encode(
                    IUniversalSlasher.InitParams({
                        isBurnerHook: false, vetoDuration: 1, resolverSetDelay: uint48(EPOCH_DURATION * 3)
                    })
                )
            })
        );

        vault = IVaultV2(vault_);
        delegator = UniversalDelegatorCompactNew(delegator_);
        slasherAddress = slasher_;
        slasher = IUniversalSlasher(slasher_);
    }

    function _createSharedSubvaultWithTwoNetworks(
        bytes32 subnetworkA,
        address operatorA,
        bytes32 subnetworkB,
        address operatorB1,
        address operatorB2
    ) internal returns (uint96 subvault) {
        uint96 networkSlot;

        subvault = delegator.createSlot(bytes32(0), 0, true, false, 20 ether);
        networkSlot = delegator.createSlot(subnetworkA, subvault, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(operatorA))), networkSlot, false, false, 10 ether);
        networkSlot = delegator.createSlot(subnetworkB, subvault, false, false, 20 ether);
        delegator.createSlot(bytes32(uint256(uint160(operatorB1))), networkSlot, false, false, 10 ether);
        delegator.createSlot(bytes32(uint256(uint160(operatorB2))), networkSlot, false, false, 10 ether);
    }

    function _runSharedOverSeed(uint256 seed) internal returns (bool found) {
        SharedOverCase memory c = _sharedOverCase(seed);
        SharedOverState memory s = _setupSharedOverState(seed, c.initialDeposit);

        if (c.withdrawal > 0) {
            _withdraw(alice, c.withdrawal);
        }
        if (c.downSize != 20 ether) {
            delegator.setSize(s.subvaults[0], c.downSize);
            delegator.setSize(s.subvaults[1], c.downSize);
        }
        if (c.waitBeforeSlash > 0) {
            vm.warp(block.timestamp + c.waitBeforeSlash);
        }

        (uint256 slash1, uint256 slash2) = _executeSharedPrimarySlashes(s, c.slashAmount);
        if (slash1 == 0 || slash2 == 0) {
            return false;
        }

        uint256 before = _totalSharedSiblingSlashable(s);

        if (c.waitAfterSlash > 0) {
            vm.warp(block.timestamp + c.waitAfterSlash);
        }
        if (c.laterDeposit > 0) {
            _deposit(alice, c.laterDeposit);
        }

        uint256 after_ = _totalSharedSiblingSlashable(s);
        if (after_ > before) {
            _reportSharedOverWitness(seed, c, before, after_);
            return true;
        }

        return false;
    }

    function _setupSharedOverState(uint256 seed, uint128 initialDeposit) internal returns (SharedOverState memory s) {
        address middleware = _seededAddress(seed, 1);
        s.middleware = middleware;
        address[4] memory networks =
            [_seededAddress(seed, 11), _seededAddress(seed, 12), _seededAddress(seed, 13), _seededAddress(seed, 14)];
        for (uint256 i = 0; i < networks.length; ++i) {
            _registerNetwork(networks[i], middleware);
            s.subnetworks[i] = networks[i].subnetwork(0);
        }

        s.operators = [
            alice,
            _seededAddress(seed, 21),
            _seededAddress(seed, 22),
            _seededAddress(seed, 23),
            _seededAddress(seed, 24),
            _seededAddress(seed, 25)
        ];

        vm.warp(2000 + seed);
        _deposit(alice, initialDeposit);

        s.subvaults[0] = _createSharedSubvaultWithTwoNetworks(
            s.subnetworks[0], s.operators[0], s.subnetworks[1], s.operators[1], s.operators[2]
        );
        s.subvaults[1] = _createSharedSubvaultWithTwoNetworks(
            s.subnetworks[2], s.operators[3], s.subnetworks[3], s.operators[4], s.operators[5]
        );
    }

    function _executeSharedPrimarySlashes(SharedOverState memory s, uint128 slashAmount)
        internal
        returns (uint256 slash1, uint256 slash2)
    {
        uint256 stake1 = slasher.slashableStake(s.subnetworks[0], s.operators[0], 0, "");
        uint256 stake2 = slasher.slashableStake(s.subnetworks[2], s.operators[3], 0, "");
        uint256 amount1 = slashAmount < stake1 ? slashAmount : stake1;
        uint256 amount2 = slashAmount < stake2 ? slashAmount : stake2;
        if (amount1 == 0 || amount2 == 0) {
            return (0, 0);
        }

        vm.startPrank(s.middleware);
        uint256 slashIndex1 = slasher.requestSlash(s.subnetworks[0], s.operators[0], amount1, 0, "");
        uint256 slashIndex2 = slasher.requestSlash(s.subnetworks[2], s.operators[3], amount2, 0, "");
        slash1 = slasher.executeSlash(slashIndex1, "");
        slash2 = slasher.executeSlash(slashIndex2, "");
        vm.stopPrank();
    }

    function _totalSharedSiblingSlashable(SharedOverState memory s) internal view returns (uint256) {
        return slasher.slashableStake(s.subnetworks[1], s.operators[1], 0, "")
            + slasher.slashableStake(s.subnetworks[1], s.operators[2], 0, "")
            + slasher.slashableStake(s.subnetworks[3], s.operators[4], 0, "")
            + slasher.slashableStake(s.subnetworks[3], s.operators[5], 0, "");
    }

    function _sharedOverCase(uint256 seed) internal pure returns (SharedOverCase memory c) {
        uint128[6] memory deposits = [uint128(20 ether), 25 ether, 30 ether, 35 ether, 40 ether, 50 ether];
        uint128[5] memory withdrawals = [uint128(0), 5 ether, 10 ether, 15 ether, 20 ether];
        uint128[5] memory downSizes = [uint128(20 ether), 15 ether, 10 ether, 5 ether, 0];
        uint128[4] memory laterDeposits = [uint128(0), 5 ether, 10 ether, 20 ether];
        uint128[3] memory slashAmounts = [uint128(5 ether), 8 ether, 10 ether];
        uint48[4] memory beforeSlashWaits = [uint48(0), HALF_DURATION, EPOCH_DURATION - 2, EPOCH_DURATION - 1];
        uint48[4] memory afterSlashWaits = [uint48(0), 1, 2, HALF_DURATION];

        c.initialDeposit = deposits[seed % deposits.length];
        c.withdrawal = withdrawals[(seed >> 3) % withdrawals.length];
        c.downSize = downSizes[(seed >> 6) % downSizes.length];
        c.laterDeposit = laterDeposits[(seed >> 9) % laterDeposits.length];
        c.slashAmount = slashAmounts[(seed >> 12) % slashAmounts.length];
        c.waitBeforeSlash = beforeSlashWaits[(seed >> 15) % beforeSlashWaits.length];
        c.waitAfterSlash = afterSlashWaits[(seed >> 18) % afterSlashWaits.length];

        if (c.withdrawal > c.initialDeposit) {
            c.withdrawal = c.initialDeposit;
        }
    }

    function _reportSharedOverWitness(uint256 seed, SharedOverCase memory c, uint256 before, uint256 after_)
        internal
        view
    {
        console2.log("shared over witness seed", seed);
        console2.log("timestamp", block.timestamp);
        console2.log("initialDeposit", uint256(c.initialDeposit));
        console2.log("withdrawal", uint256(c.withdrawal));
        console2.log("downSize", uint256(c.downSize));
        console2.log("waitBeforeSlash", uint256(c.waitBeforeSlash));
        console2.log("slashAmount", uint256(c.slashAmount));
        console2.log("waitAfterSlash", uint256(c.waitAfterSlash));
        console2.log("laterDeposit", uint256(c.laterDeposit));
        console2.log("beforeSlashable", before);
        console2.log("afterSlashable", after_);
    }

    function _seededAddress(uint256 seed, uint256 salt) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed, salt)))));
    }

    function _assertSharedSubvaultNoOverAfterFutureDeposit(
        bytes32[4] memory subnetworks,
        address[6] memory operators,
        uint96[2] memory subvaults
    ) internal view {
        uint256 slashableB1First = slasher.slashableStake(subnetworks[1], operators[1], 0, "");
        uint256 slashableB1Second = slasher.slashableStake(subnetworks[1], operators[2], 0, "");
        uint256 slashableB2First = slasher.slashableStake(subnetworks[3], operators[4], 0, "");
        uint256 slashableB2Second = slasher.slashableStake(subnetworks[3], operators[5], 0, "");
        uint256 totalSlashable = slashableB1First + slashableB1Second + slashableB2First + slashableB2Second;
        uint256 totalCurrentSubvault = delegator.getAllocated(subvaults[0], 0) + delegator.getAllocated(subvaults[1], 0);

        assertEq(vault.activeStake(), 20 ether);
        assertEq(totalCurrentSubvault, 20 ether);
        assertEq(delegator.stakeFor(subnetworks[1], operators[1], 0), 10 ether);
        assertEq(delegator.stakeFor(subnetworks[1], operators[2], 0), 0);
        assertEq(delegator.stakeFor(subnetworks[3], operators[4], 0), 10 ether);
        assertEq(delegator.stakeFor(subnetworks[3], operators[5], 0), 0);
        assertEq(slashableB1First, 10 ether);
        assertEq(slashableB1Second, 0);
        assertEq(slashableB2First, 10 ether);
        assertEq(slashableB2Second, 0);
        assertEq(totalSlashable, 20 ether);
        assertEq(totalSlashable, totalCurrentSubvault);
        assertEq(totalSlashable, vault.activeStake() + vault.activeWithdrawalsFor(0));
    }

    function _registerNetwork(address network, address middleware) internal {
        vm.startPrank(network);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _runSearch(bool withSlash) internal returns (bool found) {
        uint256 initialState = vm.snapshotState();
        uint256 seeds = withSlash ? SEEDS_WITH_SLASH : SEEDS_NO_SLASH;

        for (uint256 seed = 1; seed <= seeds; ++seed) {
            if (_runSeed(seed, withSlash)) {
                return true;
            }
            vm.revertToState(initialState);
            initialState = vm.snapshotState();
        }
    }

    function _runSeed(uint256 seed, bool withSlash) internal returns (bool found) {
        uint96[4] memory slots;
        uint128[4] memory sizes;
        address[4] memory operators;
        bool sawSlash;
        bytes32 subnetwork = _subnetwork(2000 + seed);
        (, uint96 network) = _createOperatorTree(2000 + seed);

        uint256 r0 = uint256(keccak256(abi.encode(seed, withSlash, "init")));
        vm.warp(1000 + seed);

        _deposit(alice, (((r0 >> 8) % 241) + 180) * 1 ether);

        for (uint256 i = 0; i < 4; ++i) {
            operators[i] = address(uint160(uint256(keccak256(abi.encode(seed, "operator", i)))));
            sizes[i] = uint128((((r0 >> (32 + i * 32)) % 121) + 20) * 1 ether);
            slots[i] = _createOperatorSlot(network, operators[i], sizes[i]);
        }

        if (_checkReference(seed, type(uint256).max, type(uint256).max, false, true, slots, sizes)) {
            return true;
        }

        for (uint256 step = 0; step < (withSlash ? STEPS_WITH_SLASH : STEPS_NO_SLASH); ++step) {
            (bool foundStep, bool sawSlashNext) =
                _applyStepAndCheck(seed, step, withSlash, sawSlash, subnetwork, slots, sizes, operators);
            sawSlash = sawSlashNext;
            if (foundStep) {
                return true;
            }
        }
    }

    function _runSlashBoundSearch() internal returns (bool found) {
        uint256 initialState = vm.snapshotState();

        for (uint256 seed = 1; seed <= SEEDS_WITH_SLASH; ++seed) {
            if (_runSlashBoundSeed(seed)) {
                return true;
            }
            vm.revertToState(initialState);
            initialState = vm.snapshotState();
        }
    }

    function _runSlashBoundSeed(uint256 seed) internal returns (bool found) {
        uint96[4] memory slots;
        uint128[4] memory sizes;
        address[4] memory operators;
        bytes32 subnetwork = _subnetwork(3000 + seed);
        (, uint96 network) = _createOperatorTree(3000 + seed);

        uint256 r0 = uint256(keccak256(abi.encode(seed, true, "init")));
        vm.warp(1000 + seed);
        _deposit(alice, (((r0 >> 8) % 241) + 180) * 1 ether);

        for (uint256 i = 0; i < 4; ++i) {
            operators[i] = address(uint160(uint256(keccak256(abi.encode(seed, "operator", i)))));
            sizes[i] = uint128((((r0 >> (32 + i * 32)) % 121) + 20) * 1 ether);
            slots[i] = _createOperatorSlot(network, operators[i], sizes[i]);
        }

        for (uint256 step = 0; step < STEPS_WITH_SLASH; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step, true, "step")));
            RefTriplet[4] memory beforeTriplets = _slotTriplets(slots);
            (uint256 op, SlashEffect memory effect) = _applyAction(r, true, subnetwork, slots, sizes, operators);

            if (!effect.didSlash) {
                continue;
            }

            RefTriplet[4] memory afterTriplets = _slotTriplets(slots);
            if (_checkSlashBound(
                    seed,
                    step,
                    op,
                    slots[effect.slotIndex],
                    effect.slotIndex,
                    effect.slashAmount,
                    beforeTriplets,
                    afterTriplets
                )) {
                return true;
            }
        }
    }

    function _applyStepAndCheck(
        uint256 seed,
        uint256 step,
        bool withSlash,
        bool sawSlash,
        bytes32 subnetwork,
        uint96[4] memory slots,
        uint128[4] memory sizes,
        address[4] memory operators
    ) internal returns (bool found, bool sawSlashNext) {
        uint256 r = uint256(keccak256(abi.encode(seed, step, withSlash, "step")));
        (uint256 op, SlashEffect memory effect) = _applyAction(r, withSlash, subnetwork, slots, sizes, operators);
        sawSlashNext = sawSlash || effect.didSlash;
        found = _checkReference(seed, step, op, withSlash, !withSlash || sawSlashNext, slots, sizes);
    }

    function _applyAction(
        uint256 r,
        bool withSlash,
        bytes32 subnetwork,
        uint96[4] memory slots,
        uint128[4] memory sizes,
        address[4] memory operators
    ) internal returns (uint256 op, SlashEffect memory effect) {
        op = r % (withSlash ? 6 : 5);

        if (op == 0) {
            _deposit(r % 2 == 0 ? alice : bob, ((r >> 8) % 90 + 1) * 1 ether);
            return (op, effect);
        }
        if (op == 1) {
            address user = r % 2 == 0 ? alice : bob;
            vm.prank(user);
            (bool ok,) = address(vault)
                .call(abi.encodeWithSelector(vault.withdraw.selector, user, ((r >> 8) % 90 + 1) * 1 ether));
            ok;
            return (op, effect);
        }
        if (op == 2 || op == 3) {
            uint256 idx = (r >> 16) % 4;
            uint128 cur = sizes[idx];
            uint128 newSize = op == 2
                ? uint128((uint256(cur) * ((r >> 24) % 11)) / 10)
                : cur + uint128((((r >> 24) % 40) + 1) * 1 ether);
            (bool ok,) =
                address(delegator).call(abi.encodeWithSelector(delegator.setSize.selector, slots[idx], newSize));
            if (ok) {
                sizes[idx] = newSize;
            }
            return (op, effect);
        }
        if (op == 4) {
            vm.warp(block.timestamp + waits[(r >> 32) % waits.length]);
            return (op, effect);
        }

        return (op, _applySlash(r, subnetwork, slots, sizes, operators));
    }

    function _applySlash(
        uint256 r,
        bytes32 subnetwork,
        uint96[4] memory slots,
        uint128[4] memory sizes,
        address[4] memory operators
    ) internal returns (SlashEffect memory effect) {
        uint256 idx = (r >> 16) % 4;
        uint256 requested = ((r >> 24) % 70 + 1) * 1 ether;
        uint256 slotStake = delegator.getAllocated(slots[idx], 0);
        uint256 slashAmount = _min3(requested, slotStake, vault.activeStake() + vault.activeWithdrawalsFor(0));

        if (slashAmount == 0) {
            return effect;
        }

        uint256 pending0 = delegator.getPending(slots[idx], 0);
        uint256 pendingSlashed = pending0 > slashAmount ? slashAmount : pending0;
        uint256 sizeSlashed = slashAmount - pendingSlashed;
        if (sizeSlashed > sizes[idx]) {
            sizeSlashed = sizes[idx];
        }

        vm.startPrank(slasherAddress);
        uint256 actualSlashed = delegator.onSlash(subnetwork, operators[idx], slashAmount, "");
        VaultV2(address(vault)).onSlash(actualSlashed, false);
        vm.stopPrank();

        sizes[idx] -= uint128(sizeSlashed);
        effect.didSlash = true;
        effect.slotIndex = idx;
        effect.slashAmount = actualSlashed;
        return effect;
    }

    function _slotTriplets(uint96[4] memory slots) internal view returns (RefTriplet[4] memory out) {
        for (uint256 i = 0; i < 4; ++i) {
            out[i] = _slotTriplet(slots[i]);
        }
    }

    function _slotTriplet(uint96 slot) internal view returns (RefTriplet memory out) {
        out.stake0 = delegator.getAllocated(slot, 0);
        out.stakeHalf = delegator.getAllocated(slot, HALF_DURATION);
        out.stakeMax = delegator.getAllocated(slot, MAX_DURATION);
    }

    function _checkSlashBound(
        uint256 seed,
        uint256 step,
        uint256 op,
        uint96 slot,
        uint256 slotIndex,
        uint256 slashAmount,
        RefTriplet[4] memory before,
        RefTriplet[4] memory afterTriplets
    ) internal view returns (bool found) {
        uint256[3] memory beforeVals = [
            before[slotIndex].stake0, before[slotIndex].stakeHalf, before[slotIndex].stakeMax
        ];
        uint256[3] memory afterVals =
            [afterTriplets[slotIndex].stake0, afterTriplets[slotIndex].stakeHalf, afterTriplets[slotIndex].stakeMax];
        uint48[3] memory ds = [uint48(0), HALF_DURATION, MAX_DURATION];

        for (uint256 i = 0; i < 3; ++i) {
            uint256 drop = beforeVals[i] > afterVals[i] ? beforeVals[i] - afterVals[i] : 0;
            if (drop > slashAmount) {
                console2.log("seed", seed);
                console2.log("step", step);
                console2.log("label", _opName(op, true));
                console2.log("slot", slot);
                console2.log("duration", ds[i]);
                console2.log("beforeStake", beforeVals[i]);
                console2.log("afterStake", afterVals[i]);
                console2.log("slashAmount", slashAmount);
                return true;
            }
        }
    }

    function _checkReference(
        uint256 seed,
        uint256 step,
        uint256 op,
        bool withSlash,
        bool shouldCheck,
        uint96[4] memory slots,
        uint128[4] memory sizes
    ) internal view returns (bool found) {
        if (!shouldCheck && step != type(uint256).max) {
            return false;
        }

        RefTriplet[4] memory ref = _reference(slots, sizes);

        for (uint256 i = 0; i < 4; ++i) {
            uint256 actual0 = delegator.getAllocated(slots[i], 0);
            uint256 actualHalf = delegator.getAllocated(slots[i], HALF_DURATION);
            uint256 actualMax = delegator.getAllocated(slots[i], MAX_DURATION);

            if (actual0 != ref[i].stake0 || actualHalf != ref[i].stakeHalf || actualMax != ref[i].stakeMax) {
                string memory label = step == type(uint256).max ? "initial" : _opName(op, withSlash);
                console2.log("seed", seed);
                console2.log("step", step);
                console2.log("label", label);
                console2.log("timestamp", block.timestamp);
                console2.log("slot", i + 1);
                console2.log("actual0", actual0);
                console2.log("actualHalf", actualHalf);
                console2.log("actualMax", actualMax);
                console2.log("ref0", ref[i].stake0);
                console2.log("refHalf", ref[i].stakeHalf);
                console2.log("refMax", ref[i].stakeMax);
                return true;
            }
        }
    }

    function _reportReferenceCheckpoint(string memory label, uint96[4] memory slots, uint128[4] memory sizes)
        internal
        view
    {
        RefTriplet[4] memory ref = _reference(slots, sizes);

        console2.log("checkpoint", label);
        console2.log("timestamp", block.timestamp);
        console2.log("activeStake", vault.activeStake());
        console2.log("activeWithdrawals0", vault.activeWithdrawalsFor(0));
        console2.log("activeWithdrawalsHalf", vault.activeWithdrawalsFor(HALF_DURATION));
        console2.log("activeWithdrawalsMax", vault.activeWithdrawalsFor(MAX_DURATION));

        for (uint256 i = 0; i < 4; ++i) {
            console2.log("slot", i + 1);
            console2.log("size", sizes[i]);
            console2.log("pending0", delegator.getPending(slots[i], 0));
            console2.log("pendingHalf", delegator.getPending(slots[i], HALF_DURATION));
            console2.log("pendingMax", delegator.getPending(slots[i], MAX_DURATION));
            console2.log("actual0", delegator.getAllocated(slots[i], 0));
            console2.log("actualHalf", delegator.getAllocated(slots[i], HALF_DURATION));
            console2.log("actualMax", delegator.getAllocated(slots[i], MAX_DURATION));
            console2.log("ref0", ref[i].stake0);
            console2.log("refHalf", ref[i].stakeHalf);
            console2.log("refMax", ref[i].stakeMax);
        }
    }

    function _reference(uint96[4] memory slots, uint128[4] memory sizes)
        internal
        view
        returns (RefTriplet[4] memory ref)
    {
        uint48[3] memory durations = [uint48(0), HALF_DURATION, MAX_DURATION];
        uint256[4][3] memory raw;

        for (uint256 d = 0; d < durations.length; ++d) {
            uint256 remaining = vault.activeStake() + vault.activeWithdrawalsFor(durations[d]);
            for (uint256 i = 0; i < 4; ++i) {
                uint256 own = uint256(sizes[i]) + delegator.getPending(slots[i], durations[d]);
                raw[d][i] = own > remaining ? remaining : own;
                remaining -= raw[d][i];
            }
        }

        for (uint256 i = 0; i < 4; ++i) {
            ref[i].stake0 = raw[0][i];
            ref[i].stakeHalf = raw[1][i] > ref[i].stake0 ? ref[i].stake0 : raw[1][i];
            ref[i].stakeMax = raw[2][i] > ref[i].stakeHalf ? ref[i].stakeHalf : raw[2][i];
        }
    }

    function _opName(uint256 op, bool withSlash) internal pure returns (string memory) {
        if (op == 0) return "deposit";
        if (op == 1) return "withdraw";
        if (op == 2) return "setSizeDown";
        if (op == 3) return "setSizeUp";
        if (op == 4) return "warp";
        if (withSlash && op == 5) return "slash";
        return "unknown";
    }

    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        uint256 m = a < b ? a : b;
        return m < c ? m : c;
    }
}

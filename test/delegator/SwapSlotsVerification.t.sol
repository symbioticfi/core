// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UniversalDelegatorTest} from "./UniversalDelegator.t.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

contract SwapSlotsVerificationTest is UniversalDelegatorTest {
    using UniversalDelegatorIndex for uint96;
    using Subnetwork for address;

    function test_stakeForInvariant_preSwapPendingWindow() public {
        _deposit(alice, 50);

        _createSlot(0, false, 50);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 50);
        _createSlot(subvault, false, 50);
        uint96 slot1 = subvault.createIndex(uint32(1));
        uint96 slot2 = subvault.createIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(slot1, 0);

        vm.warp(2);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, 0, EPOCH_DURATION);
    }

    function test_swapSlots_revertsReorderingAcrossPendingWindow() public {
        _deposit(alice, 50);

        _createSlot(0, false, 50);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 50);
        _createSlot(subvault, false, 50);
        uint96 slot1 = subvault.createIndex(uint32(1));
        uint96 slot2 = subvault.createIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(slot1, 0);

        vm.warp(2);
        assertEq(delegator.getAllocated(slot1, 0), 50);
        assertEq(delegator.getAllocated(slot2, 0), 0);
        assertEq(delegator.getAllocated(slot1, EPOCH_DURATION - 1), 0);
        assertEq(delegator.getAllocated(slot2, EPOCH_DURATION - 1), 0);

        vm.expectRevert(IUniversalDelegator.NotSameAllocated.selector);
        delegator.swapSlots(slot1, slot2);
    }

    function test_swapSlots_dirtyParentAfterSlash_preservesHistoricalAllocations() public {
        address carol = makeAddr("swap-dirty-carol");
        address dave = makeAddr("swap-dirty-dave");

        _deposit(alice, 260);

        bytes32 subnetwork = makeAddr("swap-dirty-subnetwork").subnetwork(0);
        _createSlot(0, false, 260);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 260);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 80);
        _createOperatorSlot(networkSlot, bob, 60);
        _createOperatorSlot(networkSlot, carol, 60);
        _createOperatorSlot(networkSlot, dave, 40);
        uint96 slot2 = networkSlot.createIndex(uint32(2));
        uint96 slot3 = networkSlot.createIndex(uint32(3));

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 10, bytes(""));

        uint48 beforeSwap = uint48(block.timestamp);
        uint256 slot2Allocated = delegator.getAllocated(slot2, 0);
        uint256 slot3Allocated = delegator.getAllocated(slot3, 0);
        vm.warp(block.timestamp + 1);

        delegator.swapSlots(slot2, slot3);

        assertEq(delegator.getAllocated(slot2, 0), slot2Allocated);
        assertEq(delegator.getAllocated(slot3, 0), slot3Allocated);
        assertEq(delegator.getAllocatedAt(slot2, 0, beforeSwap), slot2Allocated);
        assertEq(delegator.getAllocatedAt(slot3, 0, beforeSwap), slot3Allocated);
        _assertManualPrevSizeSumsMatch(networkSlot);
    }

    function test_swapSlots_dirtyParentWithPendingAndSlash_preservesDurationSensitiveReads() public {
        address carol = makeAddr("swap-pending-carol");
        address dave = makeAddr("swap-pending-dave");

        _deposit(alice, 220);

        bytes32 subnetwork = makeAddr("swap-pending-subnetwork").subnetwork(0);
        _createSlot(0, false, 220);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 220);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 80);
        _createOperatorSlot(networkSlot, bob, 40);
        _createOperatorSlot(networkSlot, carol, 40);
        _createOperatorSlot(networkSlot, dave, 40);
        uint96 slot2 = networkSlot.createIndex(uint32(2));
        uint96 slot3 = networkSlot.createIndex(uint32(3));
        uint96 slot4 = networkSlot.createIndex(uint32(4));

        vm.warp(1);
        delegator.setSize(slot2, 0);

        vm.warp(2);
        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 10, bytes(""));

        uint48 beforeSwap = uint48(block.timestamp);
        uint256 slot3Duration0 = delegator.getAllocated(slot3, 0);
        uint256 slot4Duration0 = delegator.getAllocated(slot4, 0);
        uint256 slot3DurationMax = delegator.getAllocated(slot3, EPOCH_DURATION - 1);
        uint256 slot4DurationMax = delegator.getAllocated(slot4, EPOCH_DURATION - 1);
        vm.warp(block.timestamp + 1);

        delegator.swapSlots(slot3, slot4);

        assertEq(delegator.getAllocated(slot3, 0), slot3Duration0);
        assertEq(delegator.getAllocated(slot4, 0), slot4Duration0);
        assertEq(delegator.getAllocated(slot3, EPOCH_DURATION - 1), slot3DurationMax);
        assertEq(delegator.getAllocated(slot4, EPOCH_DURATION - 1), slot4DurationMax);
        assertEq(delegator.getAllocatedAt(slot3, 0, beforeSwap), slot3Duration0);
        assertEq(delegator.getAllocatedAt(slot4, 0, beforeSwap), slot4Duration0);
        _assertManualPrevSizeSumsMatch(networkSlot);
    }
}

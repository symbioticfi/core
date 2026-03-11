// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UniversalDelegatorTest} from "./UniversalDelegator.t.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";

contract SwapSlotsVerificationTest is UniversalDelegatorTest {
    using UniversalDelegatorIndex for uint96;

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
}

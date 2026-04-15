// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";

contract UniversalDelegatorIndexHarness {
    function createIndex(uint96 parentIndex, uint32 localIndex) external pure returns (uint96) {
        return UniversalDelegatorIndex.createIndex(parentIndex, localIndex);
    }

    function getParentIndex(uint96 index) external pure returns (uint96) {
        return UniversalDelegatorIndex.getParentIndex(index);
    }

    function getChildIndex(uint96 index) external pure returns (uint32) {
        return UniversalDelegatorIndex.getChildIndex(index);
    }

    function getDepth(uint96 index) external pure returns (uint256) {
        return UniversalDelegatorIndex.getDepth(index);
    }
}

contract UniversalDelegatorIndexTest is Test {
    function test_IndexRoundTripAndRevertCases() public {
        UniversalDelegatorIndexHarness harness = new UniversalDelegatorIndexHarness();

        uint96 rootChild = harness.createIndex(0, 7);
        uint96 grandChild = harness.createIndex(rootChild, 9);

        assertEq(harness.getParentIndex(rootChild), 0);
        assertEq(harness.getChildIndex(rootChild), 7);
        assertEq(harness.getDepth(rootChild), 1);
        assertEq(harness.getParentIndex(grandChild), rootChild);
        assertEq(harness.getChildIndex(grandChild), 9);
        assertEq(harness.getDepth(grandChild), 2);

        vm.expectRevert(UniversalDelegatorIndex.NotParentIndex.selector);
        harness.createIndex(type(uint96).max, 1);

        vm.expectRevert(UniversalDelegatorIndex.ZeroIndex.selector);
        harness.getChildIndex(0);
    }
}

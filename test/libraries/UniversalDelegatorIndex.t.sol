// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";

contract UniversalDelegatorIndexHarness {
    function createIndex(uint64 parentIndex, uint32 localIndex) external pure returns (uint64) {
        return UniversalDelegatorIndex.createIndex(parentIndex, localIndex);
    }

    function getParentIndex(uint64 index) external pure returns (uint64) {
        return UniversalDelegatorIndex.getParentIndex(index);
    }

    function getChildIndex(uint64 index) external pure returns (uint32) {
        return UniversalDelegatorIndex.getChildIndex(index);
    }

    function getDepth(uint64 index) external pure returns (uint256) {
        return UniversalDelegatorIndex.getDepth(index);
    }
}

contract UniversalDelegatorIndexTest is Test {
    UniversalDelegatorIndexHarness internal harness;

    function setUp() public {
        harness = new UniversalDelegatorIndexHarness();
    }

    function test_createIndex_rootCreatesDepth1NetworkIndex() public view {
        uint32 localIndex = 7;
        uint64 expected = _depth1Index(localIndex);

        assertEq(harness.createIndex(0, localIndex), expected);
        assertEq(harness.getParentIndex(expected), 0);
        assertEq(harness.getChildIndex(expected), localIndex);
        assertEq(harness.getDepth(expected), 1);
    }

    function test_createIndex_networkCreatesDepth2OperatorIndex() public view {
        uint64 parentIndex = _depth1Index(7);
        uint32 localIndex = 9;
        uint64 expected = _depth2Index(7, localIndex);

        assertEq(harness.createIndex(parentIndex, localIndex), expected);
        assertEq(harness.getParentIndex(expected), parentIndex);
        assertEq(harness.getChildIndex(expected), localIndex);
        assertEq(harness.getDepth(expected), 2);
    }

    function test_createIndex_operatorParentReverts() public {
        uint64 operatorIndex = _depth2Index(7, 9);

        vm.expectRevert(UniversalDelegatorIndex.NotParentIndex.selector);
        harness.createIndex(operatorIndex, 11);
    }

    function test_createIndex_boundaryValues() public {
        uint32 maxLocalIndex = type(uint32).max;
        uint64 networkIndex = _depth1Index(maxLocalIndex);
        uint64 operatorIndex = _depth2Index(maxLocalIndex, maxLocalIndex);

        assertEq(harness.createIndex(0, maxLocalIndex), networkIndex);
        assertEq(harness.createIndex(networkIndex, maxLocalIndex), operatorIndex);
        assertEq(harness.getParentIndex(operatorIndex), networkIndex);
        assertEq(harness.getChildIndex(operatorIndex), maxLocalIndex);
    }

    function test_getParentIndex_zeroReverts() public {
        vm.expectRevert(UniversalDelegatorIndex.ZeroIndex.selector);
        harness.getParentIndex(0);
    }

    function test_getChildIndex_zeroReverts() public {
        vm.expectRevert(UniversalDelegatorIndex.ZeroIndex.selector);
        harness.getChildIndex(0);
    }

    function test_getDepth_zeroNetworkAndOperator() public view {
        assertEq(harness.getDepth(0), 0);
        assertEq(harness.getDepth(_depth1Index(1)), 1);
        assertEq(harness.getDepth(_depth2Index(1, 2)), 2);
    }

    function testFuzz_createIndex_rootParentBranch(uint32 localIndex) public view {
        assertEq(harness.createIndex(0, localIndex), _depth1Index(localIndex));
    }

    function testFuzz_createIndex_networkParentBranch(uint32 networkChildIndex, uint32 localIndex) public view {
        vm.assume(networkChildIndex > 0);

        uint64 parentIndex = _depth1Index(networkChildIndex);
        assertEq(harness.createIndex(parentIndex, localIndex), _depth2Index(networkChildIndex, localIndex));
    }

    function testFuzz_createIndex_invalidOperatorParentBranchReverts(
        uint32 networkChildIndex,
        uint32 operatorChildIndex,
        uint32 localIndex
    ) public {
        vm.assume(networkChildIndex > 0);
        vm.assume(operatorChildIndex > 0);

        vm.expectRevert(UniversalDelegatorIndex.NotParentIndex.selector);
        harness.createIndex(_depth2Index(networkChildIndex, operatorChildIndex), localIndex);
    }

    function testFuzz_getParentIndex(uint32 networkChildIndex, uint32 operatorChildIndex) public view {
        vm.assume(networkChildIndex > 0);
        vm.assume(operatorChildIndex > 0);

        uint64 networkIndex = _depth1Index(networkChildIndex);
        uint64 operatorIndex = _depth2Index(networkChildIndex, operatorChildIndex);

        assertEq(harness.getParentIndex(networkIndex), 0);
        assertEq(harness.getParentIndex(operatorIndex), networkIndex);
    }

    function testFuzz_getChildIndex(uint32 networkChildIndex, uint32 operatorChildIndex) public view {
        vm.assume(networkChildIndex > 0);
        vm.assume(operatorChildIndex > 0);

        assertEq(harness.getChildIndex(_depth1Index(networkChildIndex)), networkChildIndex);
        assertEq(harness.getChildIndex(_depth2Index(networkChildIndex, operatorChildIndex)), operatorChildIndex);
    }

    function _depth1Index(uint32 childIndex) internal pure returns (uint64) {
        return uint64(childIndex) << 32;
    }

    function _depth2Index(uint32 networkChildIndex, uint32 childIndex) internal pure returns (uint64) {
        return (uint64(networkChildIndex) << 32) | uint64(childIndex);
    }
}

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

contract LegacyUniversalDelegatorIndexHarness {
    function createIndex(uint96 parentIndex, uint32 localIndex) external pure returns (uint96) {
        if (parentIndex == 0) {
            return uint96(localIndex) << 64;
        }
        if (parentIndex << 32 == 0) {
            return parentIndex | uint96(localIndex) << 32;
        }
        if (parentIndex << 64 == 0) {
            return parentIndex | uint96(localIndex);
        }
        revert UniversalDelegatorIndex.NotParentIndex();
    }

    function getParentIndex(uint96 index) external pure returns (uint96) {
        if (index == 0) {
            revert UniversalDelegatorIndex.ZeroIndex();
        }
        if (index << 32 == 0) {
            return 0;
        }
        if (index << 64 == 0) {
            return index & 0xFFFFFFFF0000000000000000;
        }
        return index & 0xFFFFFFFFFFFFFFFF00000000;
    }

    function getChildIndex(uint96 index) external pure returns (uint32) {
        if (index == 0) {
            revert UniversalDelegatorIndex.ZeroIndex();
        }
        if (index << 32 == 0) {
            return uint32(index >> 64);
        }
        if (index << 64 == 0) {
            return uint32(index >> 32);
        }
        return uint32(index);
    }

    function getDepth(uint96 index) external pure returns (uint256) {
        if (index == 0) {
            return 0;
        }
        if (index << 32 == 0) {
            return 1;
        }
        if (index << 64 == 0) {
            return 2;
        }
        return 3;
    }
}

contract UniversalDelegatorIndexTest is Test {
    UniversalDelegatorIndexHarness internal harness;
    LegacyUniversalDelegatorIndexHarness internal legacyHarness;

    function setUp() public {
        harness = new UniversalDelegatorIndexHarness();
        legacyHarness = new LegacyUniversalDelegatorIndexHarness();
    }

    function test_createIndex_rootParentBranch_matchesLegacy() public {
        uint32 localIndex = 7;
        uint96 expected = _depth1Index(localIndex);

        _assertCreateIndexMatchesLegacy(0, localIndex);

        assertEq(harness.createIndex(0, localIndex), expected);
        assertEq(harness.getParentIndex(expected), 0);
        assertEq(harness.getChildIndex(expected), localIndex);
        assertEq(harness.getDepth(expected), 1);
    }

    function test_createIndex_depth1ParentBranch_matchesLegacy() public {
        uint96 parentIndex = _depth1Index(7);
        uint32 localIndex = 9;
        uint96 expected = _depth2Index(7, localIndex);

        _assertCreateIndexMatchesLegacy(parentIndex, localIndex);

        assertEq(harness.createIndex(parentIndex, localIndex), expected);
        assertEq(harness.getParentIndex(expected), parentIndex);
        assertEq(harness.getChildIndex(expected), localIndex);
        assertEq(harness.getDepth(expected), 2);
    }

    function test_createIndex_depth2ParentBranch_matchesLegacy() public {
        uint96 parentIndex = _depth2Index(7, 9);
        uint32 localIndex = 11;
        uint96 expected = _depth3Index(7, 9, localIndex);

        _assertCreateIndexMatchesLegacy(parentIndex, localIndex);

        assertEq(harness.createIndex(parentIndex, localIndex), expected);
        assertEq(harness.getParentIndex(expected), parentIndex);
        assertEq(harness.getChildIndex(expected), localIndex);
        assertEq(harness.getDepth(expected), 3);
    }

    function test_createIndex_invalidParentBranch_revertsLikeLegacy() public {
        uint96 invalidParent = _depth3Index(7, 9, 11);

        _assertCreateIndexMatchesLegacy(invalidParent, 13);

        vm.expectRevert(UniversalDelegatorIndex.NotParentIndex.selector);
        harness.createIndex(invalidParent, 13);
    }

    function test_createIndex_boundaryValues_matchLegacy() public {
        uint32 maxLocalIndex = type(uint32).max;
        uint96 depth1Parent = _depth1Index(type(uint32).max);
        uint96 depth2Parent = _depth2Index(type(uint32).max, type(uint32).max);

        _assertCreateIndexMatchesLegacy(0, maxLocalIndex);
        _assertCreateIndexMatchesLegacy(depth1Parent, maxLocalIndex);
        _assertCreateIndexMatchesLegacy(depth2Parent, maxLocalIndex);

        assertEq(harness.createIndex(0, maxLocalIndex), _depth1Index(maxLocalIndex));
        assertEq(harness.createIndex(depth1Parent, maxLocalIndex), _depth2Index(type(uint32).max, maxLocalIndex));
        assertEq(
            harness.createIndex(depth2Parent, maxLocalIndex),
            _depth3Index(type(uint32).max, type(uint32).max, maxLocalIndex)
        );
    }

    function test_manual_createIndex_expressionPlacesLocalIndexInMiddleWord() public view {
        uint96 parentIndex = _depth1Index(7);
        uint32 localIndex = 9;

        uint96 expressionResult = parentIndex | uint96(localIndex) << 32;
        uint96 parenthesizedResult = parentIndex | (uint96(localIndex) << 32);
        uint96 wrongLowWordResult = parentIndex | uint96(localIndex);
        uint96 expected = _depth2Index(7, localIndex);

        assertEq(expressionResult, parenthesizedResult);
        assertEq(expressionResult, expected);
        assertTrue(expressionResult != wrongLowWordResult);
        assertEq(harness.createIndex(parentIndex, localIndex), expected);
        assertEq(legacyHarness.createIndex(parentIndex, localIndex), expected);
    }

    function test_manual_caseMatrix_matchesLegacy() public view {
        uint96[5] memory indices =
            [uint96(0), _depth1Index(1), _depth1Index(type(uint32).max), _depth2Index(7, 9), _depth3Index(7, 9, 11)];

        for (uint256 i; i < indices.length; ++i) {
            _assertGetParentIndexMatchesLegacy(indices[i]);
            _assertGetChildIndexMatchesLegacy(indices[i]);
            assertEq(harness.getDepth(indices[i]), legacyHarness.getDepth(indices[i]));
        }

        _assertCreateIndexMatchesLegacy(0, 1);
        _assertCreateIndexMatchesLegacy(_depth1Index(7), 9);
        _assertCreateIndexMatchesLegacy(_depth2Index(7, 9), 11);
        _assertCreateIndexMatchesLegacy(_depth3Index(7, 9, 11), 13);
    }

    function test_createIndex_depth1ParentCheckMustPrecedeDepth2ParentCheck() public {
        uint96 depth1Parent = _depth1Index(7);
        uint32 localIndex = 9;

        assertEq(uint64(depth1Parent), 0);
        assertEq(uint32(depth1Parent), 0);

        uint96 expected = depth1Parent | uint96(localIndex) << 32;
        uint96 wrongOrderResult = depth1Parent | uint96(localIndex);

        assertEq(harness.createIndex(depth1Parent, localIndex), expected);
        assertEq(legacyHarness.createIndex(depth1Parent, localIndex), expected);
        assertTrue(expected != wrongOrderResult);
    }

    function test_getParentIndex_zero_revertsLikeLegacy() public {
        _assertGetParentIndexMatchesLegacy(0);

        vm.expectRevert(UniversalDelegatorIndex.ZeroIndex.selector);
        harness.getParentIndex(0);
    }

    function test_getParentIndex_depth1Branch_matchesLegacy() public {
        uint96 index = _depth1Index(7);

        _assertGetParentIndexMatchesLegacy(index);

        assertEq(harness.getParentIndex(index), 0);
    }

    function test_getParentIndex_depth2Branch_matchesLegacy() public {
        uint96 index = _depth2Index(7, 9);

        _assertGetParentIndexMatchesLegacy(index);

        assertEq(harness.getParentIndex(index), _depth1Index(7));
    }

    function test_getParentIndex_depth3Branch_matchesLegacy() public {
        uint96 index = _depth3Index(7, 9, 11);

        _assertGetParentIndexMatchesLegacy(index);

        assertEq(harness.getParentIndex(index), _depth2Index(7, 9));
    }

    function test_getChildIndex_zero_revertsLikeLegacy() public {
        _assertGetChildIndexMatchesLegacy(0);

        vm.expectRevert(UniversalDelegatorIndex.ZeroIndex.selector);
        harness.getChildIndex(0);
    }

    function test_getChildIndex_depth1Branch_matchesLegacy() public {
        uint96 index = _depth1Index(7);

        _assertGetChildIndexMatchesLegacy(index);

        assertEq(harness.getChildIndex(index), 7);
    }

    function test_getChildIndex_depth2Branch_matchesLegacy() public {
        uint96 index = _depth2Index(7, 9);

        _assertGetChildIndexMatchesLegacy(index);

        assertEq(harness.getChildIndex(index), 9);
    }

    function test_getChildIndex_depth3Branch_matchesLegacy() public {
        uint96 index = _depth3Index(7, 9, 11);

        _assertGetChildIndexMatchesLegacy(index);

        assertEq(harness.getChildIndex(index), 11);
    }

    function test_getDepth_zeroBranch_matchesLegacy() public {
        assertEq(harness.getDepth(0), legacyHarness.getDepth(0));
        assertEq(harness.getDepth(0), 0);
    }

    function test_getDepth_depth1Branch_matchesLegacy() public {
        uint96 index = _depth1Index(7);

        assertEq(harness.getDepth(index), legacyHarness.getDepth(index));
        assertEq(harness.getDepth(index), 1);
    }

    function test_getDepth_depth2Branch_matchesLegacy() public {
        uint96 index = _depth2Index(7, 9);

        assertEq(harness.getDepth(index), legacyHarness.getDepth(index));
        assertEq(harness.getDepth(index), 2);
    }

    function test_getDepth_depth3Branch_matchesLegacy() public {
        uint96 index = _depth3Index(7, 9, 11);

        assertEq(harness.getDepth(index), legacyHarness.getDepth(index));
        assertEq(harness.getDepth(index), 3);
    }

    function testFuzz_createIndex_matchesLegacy(uint96 parentIndex, uint32 localIndex) public view {
        _assertCreateIndexMatchesLegacy(parentIndex, localIndex);
    }

    function testFuzz_createIndex_rootParentBranch_matchesLegacy(uint32 localIndex) public view {
        _assertCreateIndexMatchesLegacy(0, localIndex);
    }

    function testFuzz_createIndex_depth1ParentBranch_matchesLegacy(uint32 parentChildIndex, uint32 localIndex)
        public
        view
    {
        vm.assume(parentChildIndex > 0);

        _assertCreateIndexMatchesLegacy(_depth1Index(parentChildIndex), localIndex);
    }

    function testFuzz_createIndex_depth2ParentBranch_matchesLegacy(
        uint32 rootChildIndex,
        uint32 networkChildIndex,
        uint32 localIndex
    ) public view {
        vm.assume(rootChildIndex > 0);
        vm.assume(networkChildIndex > 0);

        _assertCreateIndexMatchesLegacy(_depth2Index(rootChildIndex, networkChildIndex), localIndex);
    }

    function testFuzz_createIndex_invalidParentBranch_revertsLikeLegacy(uint96 parentIndex, uint32 localIndex)
        public
        view
    {
        vm.assume(parentIndex != 0);
        vm.assume(uint32(parentIndex) != 0);

        _assertCreateIndexMatchesLegacy(parentIndex, localIndex);
    }

    function testFuzz_getParentIndex_matchesLegacy(uint96 index) public view {
        _assertGetParentIndexMatchesLegacy(index);
    }

    function testFuzz_getChildIndex_matchesLegacy(uint96 index) public view {
        _assertGetChildIndexMatchesLegacy(index);
    }

    function testFuzz_getDepth_matchesLegacy(uint96 index) public view {
        assertEq(harness.getDepth(index), legacyHarness.getDepth(index));
    }

    function _assertCreateIndexMatchesLegacy(uint96 parentIndex, uint32 localIndex) internal view {
        (bool success, bytes memory data) = _callCreateIndex(address(harness), parentIndex, localIndex);
        (bool legacySuccess, bytes memory legacyData) =
            _callCreateIndex(address(legacyHarness), parentIndex, localIndex);

        assertEq(success, legacySuccess);
        assertEq(data, legacyData);
    }

    function _assertGetParentIndexMatchesLegacy(uint96 index) internal view {
        (bool success, bytes memory data) = _callGetParentIndex(address(harness), index);
        (bool legacySuccess, bytes memory legacyData) = _callGetParentIndex(address(legacyHarness), index);

        assertEq(success, legacySuccess);
        assertEq(data, legacyData);
    }

    function _assertGetChildIndexMatchesLegacy(uint96 index) internal view {
        (bool success, bytes memory data) = _callGetChildIndex(address(harness), index);
        (bool legacySuccess, bytes memory legacyData) = _callGetChildIndex(address(legacyHarness), index);

        assertEq(success, legacySuccess);
        assertEq(data, legacyData);
    }

    function _callCreateIndex(address target, uint96 parentIndex, uint32 localIndex)
        internal
        view
        returns (bool success, bytes memory data)
    {
        return target.staticcall(abi.encodeCall(UniversalDelegatorIndexHarness.createIndex, (parentIndex, localIndex)));
    }

    function _callGetParentIndex(address target, uint96 index) internal view returns (bool success, bytes memory data) {
        return target.staticcall(abi.encodeCall(UniversalDelegatorIndexHarness.getParentIndex, (index)));
    }

    function _callGetChildIndex(address target, uint96 index) internal view returns (bool success, bytes memory data) {
        return target.staticcall(abi.encodeCall(UniversalDelegatorIndexHarness.getChildIndex, (index)));
    }

    function _depth1Index(uint32 childIndex) internal pure returns (uint96) {
        return uint96(childIndex) << 64;
    }

    function _depth2Index(uint32 rootChildIndex, uint32 childIndex) internal pure returns (uint96) {
        return (uint96(rootChildIndex) << 64) | (uint96(childIndex) << 32);
    }

    function _depth3Index(uint32 rootChildIndex, uint32 networkChildIndex, uint32 childIndex)
        internal
        pure
        returns (uint96)
    {
        return (uint96(rootChildIndex) << 64) | (uint96(networkChildIndex) << 32) | uint96(childIndex);
    }
}

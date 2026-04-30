// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title UniversalDelegatorIndex
 * @notice Library implementing a hierarchical slot index encoding and decoding helper set.
 */
library UniversalDelegatorIndex {
    error NotParentIndex();
    error ZeroIndex();

    function createIndex(uint64 parentIndex, uint32 localIndex) internal pure returns (uint64) {
        if (parentIndex == 0) {
            return uint64(localIndex) << 32;
        }
        if (uint32(parentIndex) == 0) {
            return parentIndex | uint64(localIndex);
        }
        revert NotParentIndex();
    }

    function getParentIndex(uint64 index) internal pure returns (uint64) {
        if (index == 0) {
            revert ZeroIndex();
        }
        if (uint32(index) == 0) {
            return 0;
        }
        return index & 0xFFFFFFFF00000000;
    }

    function getChildIndex(uint64 index) internal pure returns (uint32) {
        if (index == 0) {
            revert ZeroIndex();
        }
        if (uint32(index) == 0) {
            return uint32(index >> 32);
        }
        return uint32(index);
    }

    function getDepth(uint64 index) internal pure returns (uint256) {
        if (index == 0) {
            return 0;
        }
        if (uint32(index) == 0) {
            return 1;
        }
        return 2;
    }
}

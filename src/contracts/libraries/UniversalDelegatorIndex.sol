// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library UniversalDelegatorIndex {
    error NotParentIndex();
    error ZeroIndex();

    function createIndex(uint96 parentIndex, uint32 localIndex) internal pure returns (uint96) {
        if (parentIndex == 0) {
            return uint96(localIndex) << 64;
        }
        if (parentIndex << 32 == 0) {
            return parentIndex | uint96(localIndex) << 32;
        }
        if (parentIndex << 64 == 0) {
            return parentIndex | uint96(localIndex);
        }
        revert NotParentIndex();
    }

    function getParentIndex(uint96 index) internal pure returns (uint96) {
        if (index == 0) {
            revert ZeroIndex();
        }
        if (index << 32 == 0) {
            return 0;
        }
        if (index << 64 == 0) {
            return index & 0xFFFFFFFF0000000000000000;
        }
        return index & 0xFFFFFFFFFFFFFFFF00000000;
    }

    function getChildIndex(uint96 index) internal pure returns (uint32) {
        if (index == 0) {
            revert ZeroIndex();
        }
        if (index << 32 == 0) {
            return uint32(index >> 64);
        }
        if (index << 64 == 0) {
            return uint32(index >> 32);
        }
        return uint32(index);
    }

    function getDepth(uint96 index) internal pure returns (uint256) {
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

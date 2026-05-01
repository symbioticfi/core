// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Checkpoints as CheckpointsV2} from "../libraries/CheckpointsV2.sol";

/// @title FenwickTreeLibrary
/// @notice Implements a 0-indexed Fenwick Tree (Binary Indexed Tree) for prefix sum operations.
/// @dev Enables efficient updates and prefix sum queries over a dynamic array.
///
/// # Overview
/// Fenwick Tree is a compact data structure optimized for cumulative frequency computations:
/// - `update(i, delta)` increments the element at index `i` by signed `delta`.
/// - `prefixSum(i)` returns the sum of elements in the range `[0, i]`.
///
/// This library provides:
/// - `O(log n)` time complexity for updates and prefix queries.
/// - `O(1)` fixed cost for extending the tree by doubling its capacity.
/// - Support only for arrays whose lengths are powers of two (2^k).
///
/// # References
/// - https://cp-algorithms.com/data_structures/fenwick.html
/// - https://en.wikipedia.org/wiki/Fenwick_tree
/// @author Modified from FenwickTreeLibrary (https://github.com/mellow-finance/flexible-vaults/blob/main/src/libraries/FenwickTreeLibrary.sol)
library FenwickTreeCheckpoints {
    using CheckpointsV2 for CheckpointsV2.Trace208;
    using FenwickTreeCheckpoints for Tree;

    /// @notice Thrown when initializing with an invalid length (must be power of 2 and nonzero), or during overflow.
    error InvalidLength();

    /// @notice Thrown when an index is outside the bounds of the tree.
    error IndexOutOfBounds();

    /// @notice Internal Fenwick Tree structure using a mapping as a flat array.
    struct Tree {
        /// @notice Mapping of index to its cumulative value.
        mapping(uint256 index => CheckpointsV2.Trace208) _values;
        /// @notice Length of the tree (must be a power of 2).
        uint256 _length;
    }

    /// @notice Initializes the tree with a given length (must be > 0 and power of 2).
    /// @param tree The Fenwick tree to initialize.
    /// @param length_ The length of the tree.
    function initialize(Tree storage tree, uint256 length_) internal {
        if (tree._length != 0 || length_ == 0 || (length_ & (length_ - 1)) != 0) {
            revert InvalidLength();
        }
        tree._length = length_;
    }

    /// @notice Returns the current size of the tree.
    /// @param tree The Fenwick tree.
    /// @return The length of the tree.
    function length(Tree storage tree) internal view returns (uint256) {
        return tree._length;
    }

    /// @notice Return the current sum across the whole tree, or zero for an uninitialized tree.
    /// @param tree The Fenwick tree.
    /// @return The sum of all elements in the tree.
    function total(Tree storage tree) internal view returns (uint256) {
        uint256 length = tree.length();
        return length > 0 ? tree.get(length - 1) : 0;
    }

    /// @notice Doubles the length of the Fenwick tree while preserving internal state.
    /// @param tree The Fenwick tree to be extended.
    function extend(Tree storage tree) internal {
        uint256 length_ = tree._length;
        if (length_ >= (1 << 255)) {
            revert InvalidLength();
        }
        tree._length = length_ << 1;
        tree._values[(length_ << 1) - 1].push(uint48(block.timestamp), tree._values[length_ - 1].latest());
    }

    /// @notice Updates the tree at the specified index by a given delta.
    /// @param tree The Fenwick tree.
    /// @param index Index to modify.
    /// @param value Value to add (can be negative).
    function modify(Tree storage tree, uint256 index, int256 value) internal {
        modify(tree, index, value, uint48(block.timestamp));
    }

    /// @notice Updates the tree at the specified index by a given delta at a timestamp.
    /// @param tree The Fenwick tree.
    /// @param index Index to modify.
    /// @param value Value to add (can be negative).
    /// @param timestamp Timestamp for the checkpointed update.
    function modify(Tree storage tree, uint256 index, int256 value, uint48 timestamp) internal {
        uint256 length_ = tree._length;
        if (index >= length_) {
            revert IndexOutOfBounds();
        }
        if (value == 0) {
            return;
        }
        _modify(tree, index, length_, value, timestamp);
    }

    /// @dev Internal function to apply Fenwick update logic.
    /// @param tree The Fenwick tree.
    /// @param index Index to start updating from.
    /// @param length_ Length of the tree.
    /// @param value Value to add.
    /// @param timestamp Timestamp for the checkpointed update.
    function _modify(Tree storage tree, uint256 index, uint256 length_, int256 value, uint48 timestamp) private {
        while (index < length_) {
            CheckpointsV2.Trace208 storage trace = tree._values[index];
            trace.push(timestamp, uint208(uint256(int256(uint256(trace.latest())) + value)));
            index |= index + 1;
        }
    }

    /// @notice Returns the prefix sum from index 0 to `index` (inclusive).
    /// @param tree The Fenwick tree.
    /// @param index Right bound index for sum (inclusive).
    /// @return prefixSum The sum of values from index 0 to `index`.
    function get(Tree storage tree, uint256 index) internal view returns (uint256) {
        uint256 length_ = tree._length;
        if (index >= length_) {
            index = length_ - 1;
        }
        return _get(tree, index);
    }

    /// @notice Returns the prefix sum from index 0 to `index` (inclusive) at a timestamp.
    /// @param tree The Fenwick tree.
    /// @param index Right bound index for sum (inclusive).
    /// @param timestamp Timestamp to read.
    /// @return prefixSum The sum of values from index 0 to `index`.
    function getAt(Tree storage tree, uint256 index, uint48 timestamp) internal view returns (uint256) {
        uint256 length_ = tree._length;
        if (index >= length_) {
            index = length_ - 1;
        }
        return _get(tree, index, timestamp);
    }

    /// @dev Internal function to compute prefix sum up to `index`.
    /// @param tree The Fenwick tree.
    /// @param index Right bound index for sum (inclusive).
    /// @return prefixSum The cumulative sum up to and including `index`.
    function _get(Tree storage tree, uint256 index) private view returns (uint256 prefixSum) {
        for (; true; --index) {
            prefixSum += tree._values[index].latest();
            index &= index + 1;
            if (index == 0) {
                break;
            }
        }
    }

    /// @dev Internal function to compute prefix sum up to `index` at a timestamp.
    /// @param tree The Fenwick tree.
    /// @param index Right bound index for sum (inclusive).
    /// @param timestamp Timestamp to read.
    /// @return prefixSum The cumulative sum up to and including `index`.
    function _get(Tree storage tree, uint256 index, uint48 timestamp) private view returns (uint256 prefixSum) {
        for (; true; --index) {
            prefixSum += tree._values[index].upperLookupRecent(timestamp);
            index &= index + 1;
            if (index == 0) {
                break;
            }
        }
    }

    /// @notice Returns the sum over the interval [from, to].
    /// @param tree The Fenwick tree.
    /// @param from Left bound index (inclusive).
    /// @param to Right bound index (inclusive).
    /// @return The sum over the specified interval.
    function get(Tree storage tree, uint256 from, uint256 to) internal view returns (uint256) {
        if (from > to) {
            return 0;
        }
        return _get(tree, to) - (from == 0 ? uint256(0) : _get(tree, from - 1));
    }

    /// @notice Returns the sum over the interval [from, to] at a timestamp.
    /// @param tree The Fenwick tree.
    /// @param from Left bound index (inclusive).
    /// @param to Right bound index (inclusive).
    /// @param timestamp Timestamp to read.
    /// @return The sum over the specified interval.
    function getAt(Tree storage tree, uint256 from, uint256 to, uint48 timestamp) internal view returns (uint256) {
        if (from > to) {
            return 0;
        }
        return _get(tree, to, timestamp) - (from == 0 ? uint256(0) : _get(tree, from - 1, timestamp));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Checkpoints as OZCheckpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/**
 * @dev This library defines the `Trace*` struct, for checkpointing values as they change at different points in
 * time, and later looking up past values by key.
 */
library Checkpoints {
    using OZCheckpoints for OZCheckpoints.Trace208;

    struct Trace208 {
        OZCheckpoints.Trace208 _trace;
    }

    struct Checkpoint208 {
        uint48 _key;
        uint208 _value;
    }

    struct Trace256 {
        OZCheckpoints.Trace208 _trace;
        uint256[] _values;
    }

    struct Checkpoint256 {
        uint48 _key;
        uint256 _value;
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into a Trace208 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     */
    function push(Trace208 storage self, uint48 key, uint208 value) internal returns (uint208, uint208) {
        return self._trace.push(key, value);
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookupRecent(Trace208 storage self, uint48 key) internal view returns (uint208) {
        return self._trace.upperLookupRecent(key);
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookupRecent} that can be optimized by getting the hint
     * (index of the checkpoint with key lower or equal than the search key).
     */
    function upperLookupRecent(Trace208 storage self, uint48 key, uint32 hint) internal view returns (uint208) {
        Checkpoint208 memory hintCheckpoint = at(self, hint);
        if (hintCheckpoint._key == key) {
            return hintCheckpoint._value;
        }

        if (hintCheckpoint._key < key && (hint == length(self) - 1 || at(self, hint + 1)._key > key)) {
            return hintCheckpoint._value;
        }

        return upperLookupRecent(self, key);
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(Trace208 storage self) internal view returns (uint208) {
        return self._trace.latest();
    }

    /**
     * @dev Returns the number of checkpoint.
     */
    function length(Trace208 storage self) internal view returns (uint256) {
        return self._trace.length();
    }

    /**
     * @dev Returns checkpoint at given position.
     */
    function at(Trace208 storage self, uint32 pos) internal view returns (Checkpoint208 memory) {
        OZCheckpoints.Checkpoint208 memory checkpoint = self._trace.at(pos);
        return Checkpoint208({_key: checkpoint._key, _value: checkpoint._value});
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into a Trace256 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     */
    function push(Trace256 storage self, uint48 key, uint256 value) internal returns (uint256, uint256) {
        if (self._values.length == 0) {
            self._values.push(0);
        }

        uint256 len = self._values.length;
        self._trace.push(key, uint208(len));
        self._values.push(value);

        return (self._values[len - 1], value);
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookupRecent(Trace256 storage self, uint48 key) internal view returns (uint256) {
        uint208 idx = self._trace.upperLookupRecent(key);
        return idx != 0 ? self._values[idx] : 0;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookupRecent} that can be optimized by getting the hint
     * (index of the checkpoint with key lower or equal than the search key).
     */
    function upperLookupRecent(Trace256 storage self, uint48 key, uint32 hint) internal view returns (uint256) {
        Checkpoint256 memory hintCheckpoint = at(self, hint);
        if (hintCheckpoint._key == key) {
            return hintCheckpoint._value;
        }

        if (hintCheckpoint._key < key && (hint == length(self) - 1 || at(self, hint + 1)._key > key)) {
            return hintCheckpoint._value;
        }

        return upperLookupRecent(self, key);
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(Trace256 storage self) internal view returns (uint256) {
        uint208 idx = self._trace.latest();
        return idx != 0 ? self._values[idx] : 0;
    }

    /**
     * @dev Returns the number of checkpoint.
     */
    function length(Trace256 storage self) internal view returns (uint256) {
        return self._trace.length();
    }

    /**
     * @dev Returns checkpoint at given position.
     */
    function at(Trace256 storage self, uint32 pos) internal view returns (Checkpoint256 memory) {
        OZCheckpoints.Checkpoint208 memory checkpoint = self._trace.at(pos);
        return Checkpoint256({_key: checkpoint._key, _value: self._values[checkpoint._value]});
    }
}

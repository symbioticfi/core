// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Checkpoints as OZCheckpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @dev This library defines the `Trace*` struct, for checkpointing values as they change at different points in
 * time, and later looking up past values by key.
 */
library Checkpoints {
    using OZCheckpoints for OZCheckpoints.Trace208;

    error SystemCheckpoint();

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

    function upperLookupRecentCheckpoint(
        Trace208 storage self,
        uint48 key
    ) internal view returns (bool, uint48, uint208) {
        uint256 len = self._trace._checkpoints.length;

        uint256 low = 0;
        uint256 high = len;

        if (len > 5) {
            uint256 mid = len - Math.sqrt(len);
            if (key < _unsafeAccess(self._trace._checkpoints, mid)._key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        uint256 pos = _upperBinaryLookup(self._trace._checkpoints, key, low, high);

        if (pos == 0) {
            return (false, 0, 0);
        }

        OZCheckpoints.Checkpoint208 memory checkpoint = _unsafeAccess(self._trace._checkpoints, pos - 1);
        return (true, checkpoint._key, checkpoint._value);
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(Trace208 storage self) internal view returns (uint208) {
        return self._trace.latest();
    }

    function latestCheckpoint(Trace208 storage self) internal view returns (bool, uint48, uint208) {
        return self._trace.latestCheckpoint();
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

    function pop(Trace208 storage self) internal returns (uint208 value) {
        value = self._trace.latest();
        self._trace._checkpoints.pop();
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

    function upperLookupRecentCheckpoint(
        Trace256 storage self,
        uint48 key
    ) internal view returns (bool, uint48, uint256) {
        uint256 len = self._trace._checkpoints.length;

        uint256 low = 0;
        uint256 high = len;

        if (len > 5) {
            uint256 mid = len - Math.sqrt(len);
            if (key < _unsafeAccess(self._trace._checkpoints, mid)._key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        uint256 pos = _upperBinaryLookup(self._trace._checkpoints, key, low, high);

        if (pos == 0) {
            return (false, 0, 0);
        }

        OZCheckpoints.Checkpoint208 memory checkpoint = _unsafeAccess(self._trace._checkpoints, pos - 1);
        return (true, checkpoint._key, self._values[checkpoint._value]);
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(Trace256 storage self) internal view returns (uint256) {
        uint208 idx = self._trace.latest();
        return idx != 0 ? self._values[idx] : 0;
    }

    function latestCheckpoint(Trace256 storage self) internal view returns (bool exists, uint48 _key, uint256 _value) {
        uint256 idx;
        (exists, _key, idx) = self._trace.latestCheckpoint();
        _value = exists ? self._values[idx] : 0;
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

    function pop(Trace256 storage self) internal returns (uint256 value) {
        uint208 idx = self._trace.latest();
        if (idx == 0) {
            revert SystemCheckpoint();
        }
        value = self._values[idx];
        self._trace._checkpoints.pop();
    }
    /**
     * @dev Return the index of the last (most recent) checkpoint with key lower or equal than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */

    function _upperBinaryLookup(
        OZCheckpoints.Checkpoint208[] storage self,
        uint96 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_unsafeAccess(self, mid)._key > key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high;
    }

    /**
     * @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
     */
    function _unsafeAccess(
        OZCheckpoints.Checkpoint208[] storage self,
        uint256 pos
    ) private pure returns (OZCheckpoints.Checkpoint208 storage result) {
        assembly {
            mstore(0, self.slot)
            result.slot := add(keccak256(0, 0x20), pos)
        }
    }
}

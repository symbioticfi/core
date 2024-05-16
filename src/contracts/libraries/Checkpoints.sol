// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Checkpoints as OZCheckpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

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

    struct TraceBytes32 {
        OZCheckpoints.Trace208 _trace;
        bytes32[] _values;
    }

    struct CheckpointBytes32 {
        uint48 _key;
        bytes32 _value;
    }

    function push(Trace208 storage self, uint48 key, uint208 value) internal {
        self._trace.push(key, value);
    }

    function pop(Trace208 storage self) internal returns (uint208 value) {
        value = self._trace.latest();
        self._trace._checkpoints.pop();
    }

    function upperLookupRecent(Trace208 storage self, uint48 key) internal view returns (uint208) {
        return self._trace.upperLookupRecent(key);
    }

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

    function latest(Trace208 storage self) internal view returns (uint208) {
        return self._trace.latest();
    }

    function latestCheckpoint(Trace208 storage self) internal view returns (bool exists, uint48 _key, uint208 _value) {
        return self._trace.latestCheckpoint();
    }

    function length(Trace208 storage self) internal view returns (uint256) {
        return self._trace.length();
    }

    function at(Trace208 storage self, uint32 pos) internal view returns (Checkpoint208 memory) {
        OZCheckpoints.Checkpoint208 memory checkpoint = self._trace.at(pos);
        return Checkpoint208({_key: checkpoint._key, _value: checkpoint._value});
    }

    function push(Trace256 storage self, uint48 key, uint256 value) internal {
        if (self._values.length == 0) {
            self._trace.push(0, uint208(0));
            self._values.push(0);
        }
        self._trace.push(key, uint208(self._values.length));
        self._values.push(value);
    }

    function pop(Trace256 storage self) internal returns (uint256 value) {
        uint208 idx = self._trace.latest();
        if (idx == 0) {
            revert SystemCheckpoint();
        }
        value = self._values[idx];
        self._trace._checkpoints.pop();
    }

    function upperLookupRecent(Trace256 storage self, uint48 key) internal view returns (uint256) {
        uint208 idx = self._trace.upperLookupRecent(key);
        if (idx == 0) {
            return 0;
        }
        return self._values[idx];
    }

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

    function latest(Trace256 storage self) internal view returns (uint256) {
        uint208 idx = self._trace.latest();
        if (idx == 0) {
            return 0;
        }
        return self._values[self._trace.latest()];
    }

    function latestCheckpoint(Trace256 storage self) internal view returns (bool exists, uint48 _key, uint256 _value) {
        uint256 idx;
        (exists, _key, idx) = self._trace.latestCheckpoint();
        _value = exists ? self._values[idx] : 0;
    }

    function length(Trace256 storage self) internal view returns (uint256) {
        return self._trace.length() == 0 ? 0 : self._trace.length() - 1;
    }

    function at(Trace256 storage self, uint32 pos) internal view returns (Checkpoint256 memory) {
        OZCheckpoints.Checkpoint208 memory checkpoint = self._trace.at(pos + 1);
        return Checkpoint256({_key: checkpoint._key, _value: self._values[checkpoint._value]});
    }

    function push(TraceBytes32 storage self, uint48 key, bytes32 value) internal {
        if (self._values.length == 0) {
            self._trace.push(0, uint208(0));
            self._values.push(bytes32(0));
        }
        self._trace.push(key, uint208(self._values.length));
        self._values.push(value);
    }

    function pop(TraceBytes32 storage self) internal returns (bytes32 value) {
        uint208 idx = self._trace.latest();
        if (idx == 0) {
            revert SystemCheckpoint();
        }
        value = self._values[idx];
        self._trace._checkpoints.pop();
    }

    function upperLookupRecent(TraceBytes32 storage self, uint48 key) internal view returns (bytes32) {
        uint208 idx = self._trace.upperLookupRecent(key);
        if (idx == 0) {
            return bytes32(0);
        }
        return self._values[idx];
    }

    function upperLookupRecent(TraceBytes32 storage self, uint48 key, uint32 hint) internal view returns (bytes32) {
        CheckpointBytes32 memory hintCheckpoint = at(self, hint);
        if (hintCheckpoint._key == key) {
            return hintCheckpoint._value;
        }

        if (hintCheckpoint._key < key && (hint == length(self) - 1 || at(self, hint + 1)._key > key)) {
            return hintCheckpoint._value;
        }

        return upperLookupRecent(self, key);
    }

    function latest(TraceBytes32 storage self) internal view returns (bytes32) {
        uint208 idx = self._trace.latest();
        if (idx == 0) {
            return bytes32(0);
        }
        return self._values[idx];
    }

    function latestCheckpoint(TraceBytes32 storage self)
        internal
        view
        returns (bool exists, uint48 _key, bytes32 _value)
    {
        uint256 idx;
        (exists, _key, idx) = self._trace.latestCheckpoint();
        _value = exists ? self._values[idx] : bytes32(0);
    }

    function length(TraceBytes32 storage self) internal view returns (uint256) {
        return self._trace.length() == 0 ? 0 : self._trace.length() - 1;
    }

    function at(TraceBytes32 storage self, uint32 pos) internal view returns (CheckpointBytes32 memory) {
        OZCheckpoints.Checkpoint208 memory checkpoint = self._trace.at(pos + 1);
        return CheckpointBytes32({_key: checkpoint._key, _value: self._values[checkpoint._value]});
    }
}

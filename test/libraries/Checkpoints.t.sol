// SPDX-License-Identifier: MIT
// This file was procedurally generated from scripts/generate/templates/Checkpoints.t.js.

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "../../src/contracts/libraries/Checkpoints.sol";

contract CheckpointsTrace208Test is Test {
    using Checkpoints for Checkpoints.Trace208;

    // Maximum gap between keys used during the fuzzing tests: the `_prepareKeys` function with make sure that
    // key#n+1 is in the [key#n, key#n + _KEY_MAX_GAP] range.
    uint8 internal constant _KEY_MAX_GAP = 64;

    Checkpoints.Trace208 internal _ckpts;

    // helpers
    function _boundUint48(uint48 x, uint48 min, uint48 max) internal pure returns (uint48) {
        return SafeCast.toUint48(bound(uint256(x), uint256(min), uint256(max)));
    }

    function _prepareKeys(uint48[] memory keys, uint48 maxSpread) internal pure {
        uint48 lastKey = 0;
        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 key = _boundUint48(keys[i], lastKey, lastKey + maxSpread);
            keys[i] = key;
            lastKey = key;
        }
    }

    function _prepareKeysUnrepeated(uint48[] memory keys, uint48 maxSpread) internal pure {
        uint48 lastKey = 0;
        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 key = _boundUint48(keys[i], lastKey + 1, lastKey + maxSpread);
            keys[i] = key;
            lastKey = key;
        }
    }

    function _assertLatestCheckpoint(bool exist, uint48 key, uint208 value) internal {
        (bool _exist, uint48 _key, uint208 _value) = _ckpts.latestCheckpoint();
        assertEq(_exist, exist);
        assertEq(_key, key);
        assertEq(_value, value);
    }

    // tests
    function testPush(uint48[] memory keys, uint208[] memory values, uint48 pastKey) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        // initial state
        assertEq(_ckpts.length(), 0);
        assertEq(_ckpts.latest(), 0);
        _assertLatestCheckpoint(false, 0, 0);

        uint256 duplicates = 0;
        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 key = keys[i];
            uint208 value = values[i % values.length];
            if (i > 0 && key == keys[i - 1]) ++duplicates;

            // push
            (uint208 oldValue, uint208 newValue) = _ckpts.push(key, value);

            assertEq(oldValue, i == 0 ? 0 : values[(i - 1) % values.length]);
            assertEq(newValue, value);

            // check length & latest
            assertEq(_ckpts.length(), i + 1 - duplicates);
            assertEq(_ckpts.latest(), value);
            _assertLatestCheckpoint(true, key, value);
        }

        if (keys.length > 0) {
            uint48 lastKey = keys[keys.length - 1];
            if (lastKey > 0) {
                pastKey = _boundUint48(pastKey, 0, lastKey - 1);

                vm.expectRevert();
                this.push(pastKey, values[keys.length % values.length]);
            }
        }

        assertEq(_ckpts.pop(), values[(keys.length - 1) % values.length]);

        uint208 oldValue_ = _ckpts.latest();
        (uint208 oldValue, uint208 newValue) =
            _ckpts.push(keys[keys.length - 1], values[(keys.length - 1) % values.length]);

        assertEq(oldValue, oldValue_);
        assertEq(newValue, values[(keys.length - 1) % values.length]);
    }

    // used to test reverts
    function push(uint48 key, uint208 value) external {
        _ckpts.push(key, value);
    }

    function testLookup(uint48[] memory keys, uint208[] memory values, uint48 lookup) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        uint48 lastKey = keys.length == 0 ? 0 : keys[keys.length - 1];
        lookup = _boundUint48(lookup, 0, lastKey + _KEY_MAX_GAP);

        uint208 upper = 0;
        uint208 lower = 0;
        uint48 lowerKey = type(uint48).max;
        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 key = keys[i];
            uint208 value = values[i % values.length];

            // push
            _ckpts.push(key, value);

            // track expected result of lookups
            if (key <= lookup) {
                upper = value;
            }
            // find the first key that is not smaller than the lookup key
            if (key >= lookup && (i == 0 || keys[i - 1] < lookup)) {
                lowerKey = key;
            }
            if (key == lowerKey) {
                lower = value;
            }
        }

        assertEq(_ckpts.upperLookupRecent(lookup), upper);
    }

    function testUpperLookupRecentWithHint(
        uint48[] memory keys,
        uint208[] memory values,
        uint48 lookup,
        uint32 hintIndex
    ) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        // Build checkpoints
        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        uint32 len = uint32(_ckpts.length());
        if (len == 0) return;
        hintIndex = uint32(bound(hintIndex, 0, len - 1));

        bytes memory hint = abi.encode(hintIndex);

        uint208 resultWithHint = _ckpts.upperLookupRecent(lookup, hint);
        uint208 resultWithoutHint = _ckpts.upperLookupRecent(lookup);

        assertEq(resultWithHint, resultWithoutHint);
    }

    // Test upperLookupRecentCheckpoint without hint
    function testUpperLookupRecentCheckpoint(uint48[] memory keys, uint208[] memory values, uint48 lookup) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        // Build checkpoints
        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        // Expected values
        (bool expectedExists, uint48 expectedKey, uint208 expectedValue, uint32 expectedIndex) = (false, 0, 0, 0);
        for (uint32 i = 0; i < _ckpts.length(); ++i) {
            uint48 key = _ckpts.at(i)._key;
            uint208 value = _ckpts.at(i)._value;
            if (key <= lookup) {
                expectedExists = true;
                expectedKey = key;
                expectedValue = value;
                expectedIndex = i;
            } else {
                break;
            }
        }

        // Test function
        (bool exists, uint48 key, uint208 value, uint32 index) = _ckpts.upperLookupRecentCheckpoint(lookup);
        assertEq(exists, expectedExists);
        if (exists) {
            assertEq(key, expectedKey);
            assertEq(value, expectedValue);
            assertEq(index, expectedIndex);
        }
    }

    // Test upperLookupRecentCheckpoint with hint
    function testUpperLookupRecentCheckpointWithHint(
        uint48[] memory keys,
        uint208[] memory values,
        uint48 lookup,
        uint32 hintIndex
    ) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        // Build checkpoints
        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        uint32 len = uint32(_ckpts.length());
        if (len == 0) return;
        hintIndex = uint32(bound(hintIndex, 0, len - 1));

        bytes memory hint = abi.encode(hintIndex);

        (bool existsWithHint, uint48 keyWithHint, uint208 valueWithHint, uint32 indexWithHint) =
            _ckpts.upperLookupRecentCheckpoint(lookup, hint);
        (bool existsWithoutHint, uint48 keyWithoutHint, uint208 valueWithoutHint, uint32 indexWithoutHint) =
            _ckpts.upperLookupRecentCheckpoint(lookup);

        assertEq(existsWithHint, existsWithoutHint);
        if (existsWithHint) {
            assertEq(keyWithHint, keyWithoutHint);
            assertEq(valueWithHint, valueWithoutHint);
            assertEq(indexWithHint, indexWithoutHint);
        }
    }

    // Test latest
    function testLatest(uint48[] memory keys, uint208[] memory values) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        uint208 expectedLatest = 0;

        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
            expectedLatest = values[i % values.length];
            assertEq(_ckpts.latest(), expectedLatest);
        }
    }

    // Test latestCheckpoint
    function testLatestCheckpoint(uint48[] memory keys, uint208[] memory values) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 expectedKey = keys[i];
            uint208 expectedValue = values[i % values.length];
            _ckpts.push(expectedKey, expectedValue);

            (bool exists, uint48 key, uint208 value) = _ckpts.latestCheckpoint();
            assertTrue(exists);
            assertEq(key, expectedKey);
            assertEq(value, expectedValue);
        }
    }

    // Test length
    function testLength(uint48[] memory keys, uint208[] memory values) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        uint256 expectedLength = 0;
        for (uint256 i = 0; i < keys.length; ++i) {
            bool isDuplicate = (i > 0 && keys[i] == keys[i - 1]);
            if (!isDuplicate) {
                expectedLength += 1;
            }
            _ckpts.push(keys[i], values[i % values.length]);
            assertEq(_ckpts.length(), expectedLength);
        }
    }

    // Test at
    function testAt(uint48[] memory keys, uint208[] memory values, uint32 index) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeysUnrepeated(keys, _KEY_MAX_GAP);

        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        uint256 len = _ckpts.length();
        vm.assume(len > 0);
        index = uint32(bound(index, 0, len - 1));

        Checkpoints.Checkpoint208 memory checkpoint = _ckpts.at(index);
        assertEq(checkpoint._key, keys[index]);
        assertEq(checkpoint._value, values[index % values.length]);
    }

    // Test pop
    function testPop(uint48[] memory keys, uint208[] memory values) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        uint256 initialLength = _ckpts.length();

        if (initialLength == 0) {
            vm.expectRevert();
            _ckpts.pop();
            return;
        }

        uint208 lastValue = _ckpts.latest();
        uint208 poppedValue = _ckpts.pop();
        assertEq(poppedValue, lastValue);
        assertEq(_ckpts.length(), initialLength - 1);
    }
}

contract CheckpointsTrace256Test is Test {
    using Checkpoints for Checkpoints.Trace256;

    // Maximum gap between keys used during the fuzzing tests: the `_prepareKeys` function with make sure that
    // key#n+1 is in the [key#n, key#n + _KEY_MAX_GAP] range.
    uint8 internal constant _KEY_MAX_GAP = 64;

    Checkpoints.Trace256 internal _ckpts;

    // helpers
    function _boundUint48(uint48 x, uint48 min, uint48 max) internal pure returns (uint48) {
        return SafeCast.toUint48(bound(uint256(x), uint256(min), uint256(max)));
    }

    function _prepareKeys(uint48[] memory keys, uint48 maxSpread) internal pure {
        uint48 lastKey = 0;
        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 key = _boundUint48(keys[i], lastKey, lastKey + maxSpread);
            keys[i] = key;
            lastKey = key;
        }
    }

    function _prepareKeysUnrepeated(uint48[] memory keys, uint48 maxSpread) internal pure {
        uint48 lastKey = 0;
        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 key = _boundUint48(keys[i], lastKey + 1, lastKey + maxSpread);
            keys[i] = key;
            lastKey = key;
        }
    }

    function _assertLatestCheckpoint(bool exist, uint48 key, uint256 value) internal {
        (bool _exist, uint48 _key, uint256 _value) = _ckpts.latestCheckpoint();
        assertEq(_exist, exist);
        assertEq(_key, key);
        assertEq(_value, value);
    }

    // tests
    function testPush(uint48[] memory keys, uint256[] memory values, uint48 pastKey) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        // initial state
        assertEq(_ckpts.length(), 0);
        assertEq(_ckpts.latest(), 0);
        _assertLatestCheckpoint(false, 0, 0);

        uint256 duplicates = 0;
        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 key = keys[i];
            uint256 value = values[i % values.length];
            if (i > 0 && key == keys[i - 1]) ++duplicates;

            // push
            (uint256 oldValue, uint256 newValue) = _ckpts.push(key, value);

            assertEq(oldValue, i == 0 ? 0 : values[(i - 1) % values.length]);
            assertEq(newValue, value);

            // check length & latest
            assertEq(_ckpts.length(), i + 1 - duplicates);
            assertEq(_ckpts.latest(), value);
            _assertLatestCheckpoint(true, key, value);
        }

        if (keys.length > 0) {
            uint48 lastKey = keys[keys.length - 1];
            if (lastKey > 0) {
                pastKey = _boundUint48(pastKey, 0, lastKey - 1);

                vm.expectRevert();
                this.push(pastKey, values[keys.length % values.length]);
            }
        }

        assertEq(_ckpts.pop(), values[(keys.length - 1) % values.length]);

        uint256 oldValue_ = _ckpts.latest();
        (uint256 oldValue, uint256 newValue) =
            _ckpts.push(keys[keys.length - 1], values[(keys.length - 1) % values.length]);

        assertEq(oldValue, oldValue_);
        assertEq(newValue, values[(keys.length - 1) % values.length]);
    }

    // used to test reverts
    function push(uint48 key, uint256 value) external {
        _ckpts.push(key, value);
    }

    function testLookup(uint48[] memory keys, uint256[] memory values, uint48 lookup) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        uint48 lastKey = keys.length == 0 ? 0 : keys[keys.length - 1];
        lookup = _boundUint48(lookup, 0, lastKey + _KEY_MAX_GAP);

        uint256 upper = 0;
        uint256 lower = 0;
        uint48 lowerKey = type(uint48).max;
        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 key = keys[i];
            uint256 value = values[i % values.length];

            // push
            _ckpts.push(key, value);

            // track expected result of lookups
            if (key <= lookup) {
                upper = value;
            }
            // find the first key that is not smaller than the lookup key
            if (key >= lookup && (i == 0 || keys[i - 1] < lookup)) {
                lowerKey = key;
            }
            if (key == lowerKey) {
                lower = value;
            }
        }

        assertEq(_ckpts.upperLookupRecent(lookup), upper);
    }

    function testUpperLookupRecentWithHint(
        uint48[] memory keys,
        uint256[] memory values,
        uint48 lookup,
        uint32 hintIndex
    ) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        // Build checkpoints
        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        uint32 len = uint32(_ckpts.length());
        if (len == 0) return;
        hintIndex = uint32(bound(hintIndex, 0, len - 1));

        bytes memory hint = abi.encode(hintIndex);

        uint256 resultWithHint = _ckpts.upperLookupRecent(lookup, hint);
        uint256 resultWithoutHint = _ckpts.upperLookupRecent(lookup);

        assertEq(resultWithHint, resultWithoutHint);
    }

    // Test upperLookupRecentCheckpoint without hint
    function testUpperLookupRecentCheckpoint(uint48[] memory keys, uint256[] memory values, uint48 lookup) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        // Build checkpoints
        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        // Expected values
        (bool expectedExists, uint48 expectedKey, uint256 expectedValue, uint32 expectedIndex) = (false, 0, 0, 0);
        for (uint32 i = 0; i < _ckpts.length(); ++i) {
            uint48 key = _ckpts.at(i)._key;
            uint256 value = _ckpts.at(i)._value;
            if (key <= lookup) {
                expectedExists = true;
                expectedKey = key;
                expectedValue = value;
                expectedIndex = i;
            } else {
                break;
            }
        }

        // Test function
        (bool exists, uint48 key, uint256 value, uint32 index) = _ckpts.upperLookupRecentCheckpoint(lookup);
        assertEq(exists, expectedExists);
        if (exists) {
            assertEq(key, expectedKey);
            assertEq(value, expectedValue);
            assertEq(index, expectedIndex);
        }
    }

    // Test upperLookupRecentCheckpoint with hint
    function testUpperLookupRecentCheckpointWithHint(
        uint48[] memory keys,
        uint256[] memory values,
        uint48 lookup,
        uint32 hintIndex
    ) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        // Build checkpoints
        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        uint32 len = uint32(_ckpts.length());
        if (len == 0) return;
        hintIndex = uint32(bound(hintIndex, 0, len - 1));

        bytes memory hint = abi.encode(hintIndex);

        (bool existsWithHint, uint48 keyWithHint, uint256 valueWithHint, uint32 indexWithHint) =
            _ckpts.upperLookupRecentCheckpoint(lookup, hint);
        (bool existsWithoutHint, uint48 keyWithoutHint, uint256 valueWithoutHint, uint32 indexWithoutHint) =
            _ckpts.upperLookupRecentCheckpoint(lookup);

        assertEq(existsWithHint, existsWithoutHint);
        if (existsWithHint) {
            assertEq(keyWithHint, keyWithoutHint);
            assertEq(valueWithHint, valueWithoutHint);
            assertEq(indexWithHint, indexWithoutHint);
        }
    }

    // Test latest
    function testLatest(uint48[] memory keys, uint256[] memory values) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        uint256 expectedLatest = 0;

        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
            expectedLatest = values[i % values.length];
            assertEq(_ckpts.latest(), expectedLatest);
        }
    }

    // Test latestCheckpoint
    function testLatestCheckpoint(uint48[] memory keys, uint256[] memory values) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        for (uint256 i = 0; i < keys.length; ++i) {
            uint48 expectedKey = keys[i];
            uint256 expectedValue = values[i % values.length];
            _ckpts.push(expectedKey, expectedValue);

            (bool exists, uint48 key, uint256 value) = _ckpts.latestCheckpoint();
            assertTrue(exists);
            assertEq(key, expectedKey);
            assertEq(value, expectedValue);
        }
    }

    // Test length
    function testLength(uint48[] memory keys, uint256[] memory values) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        uint256 expectedLength = 0;
        for (uint256 i = 0; i < keys.length; ++i) {
            bool isDuplicate = (i > 0 && keys[i] == keys[i - 1]);
            if (!isDuplicate) {
                expectedLength += 1;
            }
            _ckpts.push(keys[i], values[i % values.length]);
            assertEq(_ckpts.length(), expectedLength);
        }
    }

    // Test at
    function testAt(uint48[] memory keys, uint256[] memory values, uint32 index) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeysUnrepeated(keys, _KEY_MAX_GAP);

        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        uint256 len = _ckpts.length();
        vm.assume(len > 0);
        index = uint32(bound(index, 0, len - 1));

        Checkpoints.Checkpoint256 memory checkpoint = _ckpts.at(index);
        assertEq(checkpoint._key, keys[index]);
        assertEq(checkpoint._value, values[index % values.length]);
    }

    // Test pop
    function testPop(uint48[] memory keys, uint256[] memory values) public {
        vm.assume(values.length > 0 && values.length <= keys.length);
        _prepareKeys(keys, _KEY_MAX_GAP);

        for (uint256 i = 0; i < keys.length; ++i) {
            _ckpts.push(keys[i], values[i % values.length]);
        }

        uint256 initialLength = _ckpts.length();

        if (initialLength == 0) {
            vm.expectRevert();
            _ckpts.pop();
            return;
        }

        uint256 lastValue = _ckpts.latest();
        uint256 poppedValue = _ckpts.pop();
        assertEq(poppedValue, lastValue);
        assertEq(_ckpts.length(), initialLength - 1);
    }
}

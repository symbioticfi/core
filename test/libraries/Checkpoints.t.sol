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
}

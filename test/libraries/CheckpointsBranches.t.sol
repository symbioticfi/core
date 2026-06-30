// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Checkpoints as CheckpointsV1} from "../../src/contracts/libraries/Checkpoints.sol";
import {Checkpoints as CheckpointsV2} from "../../src/contracts/libraries/CheckpointsV2.sol";

contract CheckpointsV1BranchesTest is Test {
    using CheckpointsV1 for CheckpointsV1.Trace208;
    using CheckpointsV1 for CheckpointsV1.Trace256;

    CheckpointsV1.Trace208 internal _trace208;
    CheckpointsV1.Trace256 internal _trace256;

    function _seed208() internal {
        _trace208.push(10, 100);
        _trace208.push(20, 200);
        _trace208.push(30, 300);
        _trace208.push(40, 400);
        _trace208.push(50, 500);
        _trace208.push(60, 600);
    }

    function _seed256() internal {
        _trace256.push(10, 1000);
        _trace256.push(20, 2000);
        _trace256.push(30, 3000);
        _trace256.push(40, 4000);
        _trace256.push(50, 5000);
        _trace256.push(60, 6000);
    }

    function popEmptyTrace256() external {
        _trace256.pop();
    }

    function test_trace208_hintBranchesAndBoundaryLookups() public {
        _seed208();

        assertEq(_trace208.upperLookupRecent(25, bytes("")), 200);
        assertEq(_trace208.upperLookupRecent(20, abi.encode(uint32(1))), 200);
        assertEq(_trace208.upperLookupRecent(25, abi.encode(uint32(1))), 200);
        assertEq(_trace208.upperLookupRecent(25, abi.encode(uint32(4))), 200);

        (bool existsBefore,,,) = _trace208.upperLookupRecentCheckpoint(5);
        assertFalse(existsBefore);

        (bool exactExists, uint48 exactKey, uint208 exactValue, uint32 exactIndex) =
            _trace208.upperLookupRecentCheckpoint(20, abi.encode(uint32(1)));
        assertTrue(exactExists);
        assertEq(exactKey, 20);
        assertEq(exactValue, 200);
        assertEq(exactIndex, 1);

        (bool rangeExists, uint48 rangeKey, uint208 rangeValue, uint32 rangeIndex) =
            _trace208.upperLookupRecentCheckpoint(25, abi.encode(uint32(1)));
        assertTrue(rangeExists);
        assertEq(rangeKey, 20);
        assertEq(rangeValue, 200);
        assertEq(rangeIndex, 1);

        (bool emptyHintExists, uint48 emptyHintKey, uint208 emptyHintValue, uint32 emptyHintIndex) =
            _trace208.upperLookupRecentCheckpoint(25, bytes(""));
        assertTrue(emptyHintExists);
        assertEq(emptyHintKey, 20);
        assertEq(emptyHintValue, 200);
        assertEq(emptyHintIndex, 1);

        (bool fallbackExists, uint48 fallbackKey, uint208 fallbackValue, uint32 fallbackIndex) =
            _trace208.upperLookupRecentCheckpoint(25, abi.encode(uint32(4)));
        assertTrue(fallbackExists);
        assertEq(fallbackKey, 20);
        assertEq(fallbackValue, 200);
        assertEq(fallbackIndex, 1);

        (bool lowBranchExists, uint48 lowBranchKey,,) = _trace208.upperLookupRecentCheckpoint(15);
        assertTrue(lowBranchExists);
        assertEq(lowBranchKey, 10);

        (bool highBranchExists, uint48 highBranchKey,,) = _trace208.upperLookupRecentCheckpoint(55);
        assertTrue(highBranchExists);
        assertEq(highBranchKey, 50);
    }

    function test_trace256_hintBranchesAndEmptyPopRevert() public {
        _seed256();

        assertEq(_trace256.upperLookupRecent(25, bytes("")), 2000);
        assertEq(_trace256.upperLookupRecent(20, abi.encode(uint32(1))), 2000);
        assertEq(_trace256.upperLookupRecent(25, abi.encode(uint32(1))), 2000);
        assertEq(_trace256.upperLookupRecent(25, abi.encode(uint32(4))), 2000);

        (bool existsBefore,,,) = _trace256.upperLookupRecentCheckpoint(5);
        assertFalse(existsBefore);

        (bool exactExists, uint48 exactKey, uint256 exactValue, uint32 exactIndex) =
            _trace256.upperLookupRecentCheckpoint(20, abi.encode(uint32(1)));
        assertTrue(exactExists);
        assertEq(exactKey, 20);
        assertEq(exactValue, 2000);
        assertEq(exactIndex, 1);

        (bool rangeExists, uint48 rangeKey, uint256 rangeValue, uint32 rangeIndex) =
            _trace256.upperLookupRecentCheckpoint(25, abi.encode(uint32(1)));
        assertTrue(rangeExists);
        assertEq(rangeKey, 20);
        assertEq(rangeValue, 2000);
        assertEq(rangeIndex, 1);

        (bool emptyHintExists, uint48 emptyHintKey, uint256 emptyHintValue, uint32 emptyHintIndex) =
            _trace256.upperLookupRecentCheckpoint(25, bytes(""));
        assertTrue(emptyHintExists);
        assertEq(emptyHintKey, 20);
        assertEq(emptyHintValue, 2000);
        assertEq(emptyHintIndex, 1);

        (bool fallbackExists, uint48 fallbackKey, uint256 fallbackValue, uint32 fallbackIndex) =
            _trace256.upperLookupRecentCheckpoint(25, abi.encode(uint32(4)));
        assertTrue(fallbackExists);
        assertEq(fallbackKey, 20);
        assertEq(fallbackValue, 2000);
        assertEq(fallbackIndex, 1);

        (bool lowBranchExists, uint48 lowBranchKey,,) = _trace256.upperLookupRecentCheckpoint(15);
        assertTrue(lowBranchExists);
        assertEq(lowBranchKey, 10);

        (bool highBranchExists, uint48 highBranchKey,,) = _trace256.upperLookupRecentCheckpoint(55);
        assertTrue(highBranchExists);
        assertEq(highBranchKey, 50);

        assertEq(_trace256.pop(), 6000);

        CheckpointsV1.Trace256 storage emptyTrace = _trace256;
        while (emptyTrace.length() > 0) {
            emptyTrace.pop();
        }

        vm.expectRevert(CheckpointsV1.SystemCheckpoint.selector);
        this.popEmptyTrace256();
    }
}

contract CheckpointsV2BranchesTest is Test {
    using CheckpointsV2 for CheckpointsV2.Trace208;
    using CheckpointsV2 for CheckpointsV2.Trace256;
    using CheckpointsV2 for CheckpointsV2.Trace512;

    CheckpointsV2.Trace208 internal _trace208;
    CheckpointsV2.Trace256 internal _trace256;
    CheckpointsV2.Trace512 internal _trace512;

    function _seed208() internal {
        _trace208.push(10, 100);
        _trace208.push(20, 200);
        _trace208.push(30, 300);
        _trace208.push(40, 400);
        _trace208.push(50, 500);
        _trace208.push(60, 600);
    }

    function _seed256() internal {
        _trace256.push(10, 1000);
        _trace256.push(20, 2000);
        _trace256.push(30, 3000);
        _trace256.push(40, 4000);
        _trace256.push(50, 5000);
        _trace256.push(60, 6000);
    }

    function _seed512() internal {
        _trace512.push(10, [uint256(1), uint256(10)]);
        _trace512.push(20, [uint256(2), uint256(20)]);
        _trace512.push(30, [uint256(3), uint256(30)]);
        _trace512.push(40, [uint256(4), uint256(40)]);
        _trace512.push(50, [uint256(5), uint256(50)]);
        _trace512.push(60, [uint256(6), uint256(60)]);
    }

    function popEmptyTrace256() external {
        _trace256.pop();
    }

    function popEmptyTrace512() external {
        _trace512.pop();
    }

    function test_trace208_allReachableBranches() public {
        _seed208();

        assertEq(_trace208.upperLookupRecent(25, bytes("")), 200);
        assertEq(_trace208.upperLookupRecent(20, abi.encode(uint32(1))), 200);
        assertEq(_trace208.upperLookupRecent(25, abi.encode(uint32(1))), 200);
        assertEq(_trace208.upperLookupRecent(25, abi.encode(uint32(4))), 200);
        assertEq(_trace208.latest(), 600);
        assertEq(_trace208.length(), 6);
        assertEq(_trace208.at(0)._value, 100);

        (bool latestExists, uint48 latestKey, uint208 latestValue) = _trace208.latestCheckpoint();
        assertTrue(latestExists);
        assertEq(latestKey, 60);
        assertEq(latestValue, 600);

        (bool existsBefore,,,) = _trace208.upperLookupRecentCheckpoint(5);
        assertFalse(existsBefore);

        (bool exactExists, uint48 exactKey, uint208 exactValue, uint32 exactIndex) =
            _trace208.upperLookupRecentCheckpoint(20, abi.encode(uint32(1)));
        assertTrue(exactExists);
        assertEq(exactKey, 20);
        assertEq(exactValue, 200);
        assertEq(exactIndex, 1);

        (bool rangeExists, uint48 rangeKey, uint208 rangeValue, uint32 rangeIndex) =
            _trace208.upperLookupRecentCheckpoint(25, abi.encode(uint32(1)));
        assertTrue(rangeExists);
        assertEq(rangeKey, 20);
        assertEq(rangeValue, 200);
        assertEq(rangeIndex, 1);

        (bool emptyHintExists, uint48 emptyHintKey, uint208 emptyHintValue, uint32 emptyHintIndex) =
            _trace208.upperLookupRecentCheckpoint(25, bytes(""));
        assertTrue(emptyHintExists);
        assertEq(emptyHintKey, 20);
        assertEq(emptyHintValue, 200);
        assertEq(emptyHintIndex, 1);

        (bool fallbackExists, uint48 fallbackKey, uint208 fallbackValue, uint32 fallbackIndex) =
            _trace208.upperLookupRecentCheckpoint(25, abi.encode(uint32(4)));
        assertTrue(fallbackExists);
        assertEq(fallbackKey, 20);
        assertEq(fallbackValue, 200);
        assertEq(fallbackIndex, 1);

        (bool lowBranchExists, uint48 lowBranchKey,,) = _trace208.upperLookupRecentCheckpoint(15);
        assertTrue(lowBranchExists);
        assertEq(lowBranchKey, 10);

        (bool highBranchExists, uint48 highBranchKey,,) = _trace208.upperLookupRecentCheckpoint(55);
        assertTrue(highBranchExists);
        assertEq(highBranchKey, 50);

        assertEq(_trace208.pop(), 600);

        _trace208.push(60, 606);
        assertEq(_trace208.latest(), 606);
    }

    function test_trace256_allReachableBranches() public {
        _seed256();

        assertEq(_trace256.upperLookupRecent(25, bytes("")), 2000);
        assertEq(_trace256.upperLookupRecent(20, abi.encode(uint32(1))), 2000);
        assertEq(_trace256.upperLookupRecent(25, abi.encode(uint32(1))), 2000);
        assertEq(_trace256.upperLookupRecent(25, abi.encode(uint32(4))), 2000);
        assertEq(_trace256.latest(), 6000);
        assertEq(_trace256.length(), 6);
        assertEq(_trace256.at(0)._value, 1000);

        (bool latestExists, uint48 latestKey, uint256 latestValue) = _trace256.latestCheckpoint();
        assertTrue(latestExists);
        assertEq(latestKey, 60);
        assertEq(latestValue, 6000);

        (bool existsBefore,,,) = _trace256.upperLookupRecentCheckpoint(5);
        assertFalse(existsBefore);

        (bool exactExists, uint48 exactKey, uint256 exactValue, uint32 exactIndex) =
            _trace256.upperLookupRecentCheckpoint(20, abi.encode(uint32(1)));
        assertTrue(exactExists);
        assertEq(exactKey, 20);
        assertEq(exactValue, 2000);
        assertEq(exactIndex, 1);

        (bool rangeExists, uint48 rangeKey, uint256 rangeValue, uint32 rangeIndex) =
            _trace256.upperLookupRecentCheckpoint(25, abi.encode(uint32(1)));
        assertTrue(rangeExists);
        assertEq(rangeKey, 20);
        assertEq(rangeValue, 2000);
        assertEq(rangeIndex, 1);

        (bool emptyHintExists, uint48 emptyHintKey, uint256 emptyHintValue, uint32 emptyHintIndex) =
            _trace256.upperLookupRecentCheckpoint(25, bytes(""));
        assertTrue(emptyHintExists);
        assertEq(emptyHintKey, 20);
        assertEq(emptyHintValue, 2000);
        assertEq(emptyHintIndex, 1);

        (bool fallbackExists, uint48 fallbackKey, uint256 fallbackValue, uint32 fallbackIndex) =
            _trace256.upperLookupRecentCheckpoint(25, abi.encode(uint32(4)));
        assertTrue(fallbackExists);
        assertEq(fallbackKey, 20);
        assertEq(fallbackValue, 2000);
        assertEq(fallbackIndex, 1);

        (bool lowBranchExists, uint48 lowBranchKey,,) = _trace256.upperLookupRecentCheckpoint(15);
        assertTrue(lowBranchExists);
        assertEq(lowBranchKey, 10);

        (bool highBranchExists, uint48 highBranchKey,,) = _trace256.upperLookupRecentCheckpoint(55);
        assertTrue(highBranchExists);
        assertEq(highBranchKey, 50);

        assertEq(_trace256.pop(), 6000);

        _trace256.push(60, 6060);
        assertEq(_trace256.latest(), 6060);

        CheckpointsV2.Trace256 storage emptyTrace = _trace256;
        while (emptyTrace.length() > 0) {
            emptyTrace.pop();
        }

        vm.expectRevert(CheckpointsV2.SystemCheckpoint.selector);
        this.popEmptyTrace256();
    }

    function test_trace512_allReachableBranches() public {
        _seed512();

        uint256[2] memory emptyHintValue = _trace512.upperLookupRecent(25, bytes(""));
        assertEq(emptyHintValue[0], 2);
        assertEq(emptyHintValue[1], 20);

        uint256[2] memory exactHintValue = _trace512.upperLookupRecent(20, abi.encode(uint32(1)));
        assertEq(exactHintValue[0], 2);
        assertEq(exactHintValue[1], 20);

        uint256[2] memory rangeHintValue = _trace512.upperLookupRecent(25, abi.encode(uint32(1)));
        assertEq(rangeHintValue[0], 2);
        assertEq(rangeHintValue[1], 20);

        uint256[2] memory fallbackHintValue = _trace512.upperLookupRecent(25, abi.encode(uint32(4)));
        assertEq(fallbackHintValue[0], 2);
        assertEq(fallbackHintValue[1], 20);

        uint256[2] memory latestValue = _trace512.latest();
        assertEq(latestValue[0], 6);
        assertEq(latestValue[1], 60);
        assertEq(_trace512.length(), 6);

        CheckpointsV2.Checkpoint512 memory firstCheckpoint = _trace512.at(0);
        assertEq(firstCheckpoint._key, 10);
        assertEq(firstCheckpoint._value[0], 1);
        assertEq(firstCheckpoint._value[1], 10);

        (bool latestExists, uint48 latestKey, uint256[2] memory latestCheckpointValue) = _trace512.latestCheckpoint();
        assertTrue(latestExists);
        assertEq(latestKey, 60);
        assertEq(latestCheckpointValue[0], 6);
        assertEq(latestCheckpointValue[1], 60);

        (bool existsBefore,,,) = _trace512.upperLookupRecentCheckpoint(5);
        assertFalse(existsBefore);

        (bool exactExists, uint48 exactKey, uint256[2] memory exactValue, uint32 exactIndex) =
            _trace512.upperLookupRecentCheckpoint(20, abi.encode(uint32(1)));
        assertTrue(exactExists);
        assertEq(exactKey, 20);
        assertEq(exactValue[0], 2);
        assertEq(exactValue[1], 20);
        assertEq(exactIndex, 1);

        (bool rangeExists, uint48 rangeKey, uint256[2] memory rangeValue, uint32 rangeIndex) =
            _trace512.upperLookupRecentCheckpoint(25, abi.encode(uint32(1)));
        assertTrue(rangeExists);
        assertEq(rangeKey, 20);
        assertEq(rangeValue[0], 2);
        assertEq(rangeValue[1], 20);
        assertEq(rangeIndex, 1);

        (bool emptyHintExists, uint48 emptyHintKey, uint256[2] memory emptyHintCheckpointValue, uint32 emptyHintIndex) =
            _trace512.upperLookupRecentCheckpoint(25, bytes(""));
        assertTrue(emptyHintExists);
        assertEq(emptyHintKey, 20);
        assertEq(emptyHintCheckpointValue[0], 2);
        assertEq(emptyHintCheckpointValue[1], 20);
        assertEq(emptyHintIndex, 1);

        (bool fallbackExists, uint48 fallbackKey, uint256[2] memory fallbackValue, uint32 fallbackIndex) =
            _trace512.upperLookupRecentCheckpoint(25, abi.encode(uint32(4)));
        assertTrue(fallbackExists);
        assertEq(fallbackKey, 20);
        assertEq(fallbackValue[0], 2);
        assertEq(fallbackValue[1], 20);
        assertEq(fallbackIndex, 1);

        (bool lowBranchExists, uint48 lowBranchKey,,) = _trace512.upperLookupRecentCheckpoint(15);
        assertTrue(lowBranchExists);
        assertEq(lowBranchKey, 10);

        (bool highBranchExists, uint48 highBranchKey,,) = _trace512.upperLookupRecentCheckpoint(55);
        assertTrue(highBranchExists);
        assertEq(highBranchKey, 50);

        uint256[2] memory poppedValue = _trace512.pop();
        assertEq(poppedValue[0], 6);
        assertEq(poppedValue[1], 60);

        _trace512.push(50, [uint256(66), uint256(660)]);
        uint256[2] memory updatedLatest = _trace512.latest();
        assertEq(updatedLatest[0], 66);
        assertEq(updatedLatest[1], 660);

        CheckpointsV2.Trace512 storage emptyTrace = _trace512;
        while (emptyTrace.length() > 0) {
            emptyTrace.pop();
        }

        vm.expectRevert(CheckpointsV2.SystemCheckpoint.selector);
        this.popEmptyTrace512();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Math512} from "../../src/contracts/libraries/Math512.sol";

contract Math512Harness {
    function add(uint256[2] memory a, uint256 b) external pure returns (uint256[2] memory) {
        return Math512.add(a, b);
    }

    function sub(uint256[2] memory a, uint256[2] memory b) external pure returns (uint256) {
        return Math512.sub(a, b);
    }
}

contract Math512Test is Test {
    Math512Harness internal harness;

    function setUp() public {
        harness = new Math512Harness();
    }

    function _make(uint256 high, uint256 low) internal pure returns (uint256[2] memory r) {
        r[0] = high;
        r[1] = low;
    }

    function _assertEq512(uint256[2] memory a, uint256[2] memory b) internal {
        assertEq(a[0], b[0]);
        assertEq(a[1], b[1]);
    }

    function testAddNoCarry() public {
        uint256[2] memory a = _make(5, 7);
        uint256[2] memory result = harness.add(a, 11);
        _assertEq512(result, _make(5, 18));
    }

    function testAddCarry() public {
        uint256[2] memory a = _make(9, type(uint256).max);
        uint256[2] memory result = harness.add(a, 1);
        _assertEq512(result, _make(10, 0));
    }

    function testAddOverflowReverts() public {
        uint256[2] memory a = _make(type(uint256).max, type(uint256).max);
        vm.expectRevert(Math512.AddOverflow.selector);
        harness.add(a, 1);
    }

    function testAddFuzz(uint256 high, uint256 low, uint256 b) public {
        uint256 newLow;
        bool carry;
        unchecked {
            newLow = low + b;
            carry = newLow < low;
        }
        uint256 newHigh;
        unchecked {
            newHigh = high + (carry ? 1 : 0);
        }
        bool overflow = newHigh < high;

        uint256[2] memory a = _make(high, low);
        if (overflow) {
            vm.expectRevert(Math512.AddOverflow.selector);
            harness.add(a, b);
        } else {
            uint256[2] memory result = harness.add(a, b);
            _assertEq512(result, _make(newHigh, newLow));
        }
    }

    function testSubSimple() public {
        uint256[2] memory a = _make(0, 10);
        uint256[2] memory b = _make(0, 3);
        assertEq(harness.sub(a, b), 7);
    }

    function testSubBorrowWrap() public {
        uint256[2] memory a = _make(1, 0);
        uint256[2] memory b = _make(0, 1);
        assertEq(harness.sub(a, b), type(uint256).max);
    }

    function testSubFuzz(uint256 highA, uint256 lowA, uint256 highB, uint256 lowB) public {
        uint256[2] memory a = _make(highA, lowA);
        uint256[2] memory b = _make(highB, lowB);
        uint256 expected;
        unchecked {
            expected = lowA - lowB;
        }
        assertEq(harness.sub(a, b), expected);
    }
}

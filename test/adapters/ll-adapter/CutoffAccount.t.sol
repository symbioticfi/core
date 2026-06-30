// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {CutoffAccount} from "../../../src/contracts/adapters/ll-adapter/common/CutoffAccount.sol";

contract CutoffAccountHarness is CutoffAccount {
    uint48 internal constant CUTOFF = 1_785_024_000;
    uint48 internal constant AUGUST_26_2026 = 1_787_702_400;

    function timestampToBucket(uint48 timestamp) public pure override returns (uint48 bucket) {
        if (timestamp < CUTOFF) {
            return 0;
        }
        if (timestamp < AUGUST_26_2026) {
            return 1;
        }
        return 2;
    }

    function bucketToTimestamp(uint48 bucket) public pure override returns (uint48 timestamp) {
        if (bucket == 0) {
            return 0;
        }
        if (bucket == 1) {
            return CUTOFF;
        }
        return AUGUST_26_2026;
    }
}

contract CutoffAccountTest is Test {
    uint48 internal constant JULY_23_2026 = 1_784_764_800;
    uint48 internal constant JULY_26_2026 = 1_785_024_000;

    CutoffAccountHarness internal account;

    function setUp() public {
        vm.warp(JULY_23_2026);
        account = new CutoffAccountHarness();
    }

    function testCurrentBucketUsesTimestampToBucket() public view {
        assertEq(account.currentBucket(), 0);
    }

    function testNextCutoffUsesNextBucketTimestamp() public view {
        assertEq(account.nextCutoff(), JULY_26_2026);
    }

    function testBucketConversion() public view {
        assertEq(account.timestampToBucket(JULY_26_2026 - 1), 0);
        assertEq(account.timestampToBucket(JULY_26_2026), 1);
        assertEq(account.bucketToTimestamp(0), 0);
        assertEq(account.bucketToTimestamp(1), JULY_26_2026);
    }
}

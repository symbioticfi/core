// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ICutoffAccount} from "../../../../interfaces/adapters/ll-adapter/ICutoffAccount.sol";

/// @title CutoffAccount
/// @notice Mixin grouping non-instant redemption requests into cutoff buckets.
abstract contract CutoffAccount is ICutoffAccount {
    /* VIEW FUNCTIONS */

    /// @inheritdoc ICutoffAccount
    function currentBucket() public view virtual returns (uint48 bucket) {
        return timestampToBucket(uint48(block.timestamp));
    }

    function nextCutoff() public view virtual returns (uint48 timestamp) {
        return bucketToTimestamp(currentBucket() + 1);
    }

    /// @inheritdoc ICutoffAccount
    function timestampToBucket(uint48 timestamp) public view virtual override returns (uint48 bucket);

    /// @inheritdoc ICutoffAccount
    function bucketToTimestamp(uint48 bucket) public view virtual override returns (uint48 timestamp);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MigratableEntity} from "../../../../../src/contracts/common/MigratableEntity.sol";

/// @title AdapterPause
/// @notice Dummy Adapter implementation used for an emergency-freeze contracts proposal.
/// @dev Adapter business calls unconditionally revert while migration functionality remains available for recovery.
contract AdapterPause is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}

    fallback() external payable {
        revert();
    }
}

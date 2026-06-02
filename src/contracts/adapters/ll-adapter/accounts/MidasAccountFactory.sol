// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

/// @title MidasCompAccountFactory
/// @notice Migratable factory for compounding Midas account implementations.
contract MidasCompAccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

/// @title MidasNonCompAccountFactory
/// @notice Migratable factory for non-compounding Midas account implementations.
contract MidasNonCompAccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

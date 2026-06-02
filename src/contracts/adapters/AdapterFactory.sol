// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MigratablesFactory} from "../common/MigratablesFactory.sol";

import {IAdapterFactory} from "../../interfaces/adapters/IAdapterFactory.sol";

/// @title AdapterFactory
/// @notice Migratable factory for one adapter family.
contract AdapterFactory is MigratablesFactory, IAdapterFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

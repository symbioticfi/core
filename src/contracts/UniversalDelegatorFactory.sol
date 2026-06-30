// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {MigratablesFactory} from "./common/MigratablesFactory.sol";

import {IUniversalDelegatorFactory} from "../interfaces/IUniversalDelegatorFactory.sol";

/// @title UniversalDelegatorFactory
/// @notice Factory contract for migratable universal delegator deployments.
contract UniversalDelegatorFactory is MigratablesFactory, IUniversalDelegatorFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {MigratablesFactory} from "./common/MigratablesFactory.sol";

import {IVaultFactory} from "../interfaces/IVaultFactory.sol";

/// @title VaultFactory
/// @notice Factory contract for migratable vault version deployments.
contract VaultFactory is MigratablesFactory, IVaultFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

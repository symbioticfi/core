// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MigratablesFactory} from "./common/MigratablesFactory.sol";

import {IWithdrawalQueueFactory} from "../interfaces/vault/IWithdrawalQueueFactory.sol";

/// @title WithdrawalQueueFactory
/// @notice Factory contract for migratable withdrawal queue deployments.
contract WithdrawalQueueFactory is MigratablesFactory, IWithdrawalQueueFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

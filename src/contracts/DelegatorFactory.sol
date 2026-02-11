// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {Factory} from "./common/Factory.sol";

import {IDelegatorFactory} from "../interfaces/IDelegatorFactory.sol";

/// @title DelegatorFactory
/// @notice Factory contract for delegator implementation deployments.
contract DelegatorFactory is Factory, IDelegatorFactory {
    constructor(address owner_) Factory(owner_) {}
}

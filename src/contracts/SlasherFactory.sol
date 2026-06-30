// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {Factory} from "./common/Factory.sol";

import {ISlasherFactory} from "../interfaces/ISlasherFactory.sol";

/// @title SlasherFactory
/// @notice Factory contract for slasher implementation deployments.
contract SlasherFactory is Factory, ISlasherFactory {
    constructor(address owner_) Factory(owner_) {}
}

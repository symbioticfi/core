// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {Registry} from "./common/Registry.sol";

import {IOperatorRegistry} from "../interfaces/IOperatorRegistry.sol";

/// @title OperatorRegistry
/// @notice Registry contract for operator entity membership.
contract OperatorRegistry is Registry, IOperatorRegistry {
    /// @inheritdoc IOperatorRegistry
    function registerOperator() external {
        if (isEntity(msg.sender)) {
            revert OperatorAlreadyRegistered();
        }

        _addEntity(msg.sender);
    }
}

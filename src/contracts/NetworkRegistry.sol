// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {Registry} from "./common/Registry.sol";

import {INetworkRegistry} from "../interfaces/INetworkRegistry.sol";

/// @title NetworkRegistry
/// @notice Registry contract for network entity membership.
contract NetworkRegistry is Registry, INetworkRegistry {
    /// @inheritdoc INetworkRegistry
    function registerNetwork() external {
        if (isEntity(msg.sender)) {
            revert NetworkAlreadyRegistered();
        }

        _addEntity(msg.sender);
    }
}

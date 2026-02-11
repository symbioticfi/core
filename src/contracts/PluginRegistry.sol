// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {Registry} from "./common/Registry.sol";

import {IPluginRegistry} from "../interfaces/IPluginRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title PluginRegistry
/// @notice Registry contract for whitelisted plugin contracts.
contract PluginRegistry is Registry, Ownable, IPluginRegistry {
    constructor(address initOwner) Ownable(initOwner) {}

    /// @inheritdoc IPluginRegistry
    function whitelistPlugin(address plugin) external onlyOwner {
        if (isEntity(plugin)) {
            revert PluginAlreadyWhitelisted();
        }

        _addEntity(plugin);
    }
}

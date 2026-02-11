// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {Registry} from "./common/Registry.sol";

import {IPluginRegistry} from "../interfaces/IPluginRegistry.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title PluginsRegistry
/// @notice Registry contract for whitelisted plugin contracts.
contract PluginsRegistry is Registry, OwnableUpgradeable, IPluginRegistry {
    /// @inheritdoc IPluginRegistry
    function whitelistPlugin(address plugin, uint256 limit) external onlyOwner {
        if (isEntity(plugin)) {
            revert PluginAlreadyWhitelisted();
        }

        _addEntity(plugin);
    }
}

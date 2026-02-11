// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRegistry} from "./common/IRegistry.sol";

/**
 * @title IPluginRegistry
 * @notice Interface for the PluginRegistry contract.
 */
interface IPluginRegistry is IRegistry {
    /**
     * @notice Raised when trying to whitelist a plugin that is already whitelisted.
     */
    error PluginAlreadyWhitelisted();

    /**
     * @notice Whitelist a plugin contract.
     * @param plugin Address of the plugin to whitelist.
     * @dev Only the contract owner can call this function.
     */
    function whitelistPlugin(address plugin) external;
}

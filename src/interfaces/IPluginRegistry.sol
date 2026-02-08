// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRegistry} from "./common/IRegistry.sol";

interface IPluginRegistry is IRegistry {
    error PluginAlreadyWhitelisted();

    function whitelistPlugin(address plugin) external;
}

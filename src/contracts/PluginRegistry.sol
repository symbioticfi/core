// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Registry} from "./common/Registry.sol";

import {IPluginRegistry} from "../interfaces/IPluginRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PluginRegistry is Registry, Ownable, IPluginRegistry {
    constructor(address owner_) Ownable(owner_) {}

    /**
     * @inheritdoc IPluginRegistry
     */
    function whitelistPlugin(address plugin) public onlyOwner {
        if (isEntity(plugin)) {
            revert AlreadyWhitelisted();
        }

        _addEntity(plugin);
    }

    /**
     * @inheritdoc IPluginRegistry
     */
    function unwhitelistPlugin(address plugin) public onlyOwner {
        if (!isEntity(plugin)) {
            revert NotWhitelisted();
        }

        _removeEntity(plugin);
    }
}

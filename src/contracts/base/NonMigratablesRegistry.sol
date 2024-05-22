// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {INonMigratablesRegistry} from "src/interfaces/base/INonMigratablesRegistry.sol";

import {Registry} from "./Registry.sol";

contract NonMigratablesRegistry is Registry, INonMigratablesRegistry {
    /**
     * @inheritdoc INonMigratablesRegistry
     */
    function register() external {
        if (isEntity(msg.sender)) {
            revert EntityAlreadyRegistered();
        }

        _addEntity(msg.sender);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Registry} from "./common/Registry.sol";

import {INetworkRegistry} from "src/interfaces/INetworkRegistry.sol";

contract NetworkRegistry is Registry, INetworkRegistry {
    /**
     * @inheritdoc INetworkRegistry
     */
    function registerNetwork() external {
        if (isEntity(msg.sender)) {
            revert NetworkAlreadyRegistered();
        }

        _addEntity(msg.sender);
    }
}

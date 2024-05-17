// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPlugin} from "src/interfaces/IPlugin.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";

abstract contract Plugin is IPlugin {
    /**
     * @inheritdoc IPlugin
     */
    address public immutable REGISTRY;

    modifier onlyEntity() {
        if (!IRegistry(REGISTRY).isEntity(msg.sender)) {
            revert NotEntity();
        }
        _;
    }

    constructor(address registry) {
        REGISTRY = registry;
    }
}

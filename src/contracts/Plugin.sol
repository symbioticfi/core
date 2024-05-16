// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPlugin} from "src/interfaces/IPlugin.sol";
import {IFactory} from "src/interfaces/IFactory.sol";

contract Plugin is IPlugin {
    /**
     * @inheritdoc IPlugin
     */
    address public immutable REGISTRY;

    modifier onlyEntity() {
        if (!IFactory(REGISTRY).isEntity(msg.sender)) {
            revert NotEntity();
        }
        _;
    }

    constructor(address registry) {
        REGISTRY = registry;
    }
}

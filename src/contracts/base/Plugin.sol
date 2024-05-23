// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPlugin} from "src/interfaces/base/IPlugin.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

abstract contract Plugin is IPlugin {
    /**
     * @inheritdoc IPlugin
     */
    address public immutable REGISTRY;

    modifier onlyEntity() {
        _checkEntity(msg.sender);
        _;
    }

    constructor(address registry) {
        REGISTRY = registry;
    }

    function _checkEntity(address account) internal view {
        if (!IRegistry(REGISTRY).isEntity(account)) {
            revert NotEntity();
        }
    }
}

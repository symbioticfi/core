// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMiddlewarePlugin} from "src/interfaces/IMiddlewarePlugin.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

contract MiddlewarePlugin is IMiddlewarePlugin {
    /**
     * @inheritdoc IMiddlewarePlugin
     */
    address public immutable REGISTRY;

    /**
     * @inheritdoc IMiddlewarePlugin
     */
    mapping(address entity => address value) public middleware;

    constructor(address registry) {
        REGISTRY = registry;
    }

    /**
     * @inheritdoc IMiddlewarePlugin
     */
    function setMiddleware(address middleware_) external {
        if (!IRegistry(REGISTRY).isEntity(msg.sender)) {
            revert NotEntity();
        }

        if (middleware[msg.sender] == middleware_) {
            revert AlreadySet();
        }

        middleware[msg.sender] = middleware_;

        emit SetMiddleware(msg.sender, middleware_);
    }
}

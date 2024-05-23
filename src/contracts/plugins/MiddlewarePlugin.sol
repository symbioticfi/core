// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Plugin} from "src/contracts/base/Plugin.sol";

import {IMiddlewarePlugin} from "src/interfaces/plugins/IMiddlewarePlugin.sol";

contract MiddlewarePlugin is Plugin, IMiddlewarePlugin {
    /**
     * @inheritdoc IMiddlewarePlugin
     */
    mapping(address entity => address value) public middleware;

    constructor(address registry) Plugin(registry) {}

    /**
     * @inheritdoc IMiddlewarePlugin
     */
    function setMiddleware(address middleware_) external onlyEntity {
        if (middleware[msg.sender] == middleware_) {
            revert AlreadySet();
        }

        middleware[msg.sender] = middleware_;

        emit SetMiddleware(msg.sender, middleware_);
    }
}

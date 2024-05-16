// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMiddlewarePlugin} from "src/interfaces/plugins/IMiddlewarePlugin.sol";

import {Plugin} from "src/contracts/Plugin.sol";

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
        middleware[msg.sender] = middleware_;

        emit SetMiddleware(msg.sender, middleware_);
    }
}

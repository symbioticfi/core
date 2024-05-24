// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMiddlewareService} from "src/interfaces/IMiddlewareService.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

contract MiddlewareService is IMiddlewareService {
    /**
     * @inheritdoc IMiddlewareService
     */
    address public immutable REGISTRY;

    /**
     * @inheritdoc IMiddlewareService
     */
    mapping(address entity => address value) public middleware;

    constructor(address registry) {
        REGISTRY = registry;
    }

    /**
     * @inheritdoc IMiddlewareService
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

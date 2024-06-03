// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {INetworkMiddlewareService} from "src/interfaces/INetworkMiddlewareService.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

contract NetworkMiddlewareService is INetworkMiddlewareService {
    /**
     * @inheritdoc INetworkMiddlewareService
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc INetworkMiddlewareService
     */
    mapping(address network => address value) public middleware;

    constructor(address networkRegistry) {
        NETWORK_REGISTRY = networkRegistry;
    }

    /**
     * @inheritdoc INetworkMiddlewareService
     */
    function setMiddleware(address middleware_) external {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        if (middleware[msg.sender] == middleware_) {
            revert AlreadySet();
        }

        middleware[msg.sender] = middleware_;

        emit SetMiddleware(msg.sender, middleware_);
    }
}

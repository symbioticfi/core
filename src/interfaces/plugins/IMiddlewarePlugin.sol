// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPlugin} from "src/interfaces/IPlugin.sol";

interface IMiddlewarePlugin is IPlugin {
    error AlreadySet();

    /**
     * @notice Emitted when a middleware is set for an entity.
     * @param entity address of the entity
     * @param middleware new middleware of the entity
     */
    event SetMiddleware(address indexed entity, address middleware);

    /**
     * @notice Get an entity's middleware.
     * @param entity address of the entity
     * @return middleware of the entity
     */
    function middleware(address entity) external view returns (address);

    /**
     * @notice Set a new middleware for a calling entity.
     * @param middleware new middleware of the entity
     */
    function setMiddleware(address middleware) external;
}

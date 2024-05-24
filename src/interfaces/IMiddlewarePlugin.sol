// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IMiddlewarePlugin {
    error AlreadySet();
    error NotEntity();

    /**
     * @notice Emitted when a middleware is set for an entity.
     * @param entity address of the entity
     * @param middleware new middleware of the entity
     */
    event SetMiddleware(address indexed entity, address middleware);

    /**
     * @notice Get the registry address.
     * @return address of the registry
     */
    function REGISTRY() external view returns (address);

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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title INetworkMiddlewareService
 * @notice Interface for the NetworkMiddlewareService contract.
 */
interface INetworkMiddlewareService {
    error AlreadySet();
    error NotNetwork();

    /**
     * @notice Emitted when a middleware is set for a network.
     * @param network Address of the network.
     * @param middleware New middleware of the network.
     */
    event SetMiddleware(address indexed network, address middleware);

    /**
     * @notice Get the network registry's address.
     * @return Address Of the network registry.
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get a given network's middleware.
     * @param network Address of the network.
     * @return Middleware Of the network.
     */
    function middleware(address network) external view returns (address);

    /**
     * @notice Set a new middleware for a calling network.
     * @param middleware New middleware of the network.
     */
    function setMiddleware(address middleware) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "./IRegistry.sol";

interface INonMigratablesFactory is IRegistry {
    error AlreadyWhitelisted();
    
    /**
     * @notice Get the total number of whitelisted implementations.
     * @return total number of implementations
     */
    function totalImplementations() external view returns (uint64);

    /**
     * @notice Get the implementation for a given index.
     * @param index position to get the implementation at
     * @return address of the implementation
     */
    function implementation(uint64 index) external view returns (address);

    /**
     * @notice Whitelist a new implementation for entities.
     * @param newImplementation address of the new implementation
     */
    function whitelist(address newImplementation) external;

    /**
     * @notice Create a new entity at the registry.
     * @param index `index`th implementation to use
     * @param data initial data for the entity creation
     * @return address of the entity
     */
    function create(uint64 index, bytes memory data) external returns (address);

}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "./IRegistry.sol";

interface IMigratablesFactory is IRegistry {
    error AlreadyWhitelisted();
    error InvalidVersion();
    error NotOwner();

    /**
     * @notice Get the last available version.
     * @return version of the last implementation
     * @dev If zero, no implementations are whitelisted.
     */
    function lastVersion() external view returns (uint64);

    /**
     * @notice Get the implementation for a given version.
     * @param version version to get the implementation for
     * @return address of the implementation
     */
    function implementation(uint64 version) external view returns (address);

    /**
     * @notice Whitelist a new implementation for entities.
     * @param entityImplementation address of the new implementation
     */
    function whitelist(address entityImplementation) external;

    /**
     * @notice Migrate a given entity to the next version.
     * @param entity address of the entity to migrate
     * @param data some data to reinitialize the contract with
     * @dev Only the entity's owner can call this function.
     */
    function migrate(address entity, bytes memory data) external;

    /**
     * @notice Create a new entity at the registry.
     * @param version entity's version to use
     * @param data initial data for the entity creation
     * @return address of the entity
     */
    function create(uint64 version, bytes memory data) external returns (address);
}

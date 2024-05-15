// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFactory} from "./IFactory.sol";

interface IMigratablesRegistry is IFactory {
    error AlreadyWhitelisted();
    error AlreadyUpToDate();
    error ImproperOwner();
    error InvalidVersion();

    /**
     * @notice Get a given entity's version.
     * @param entity address of the entity
     * @return version of the entity
     * @dev Starts from 1.
     */
    function version(address entity) external view returns (uint256);

    /**
     * @notice Get a maximum whitelisted version.
     * @return maximum version
     * @dev If zero, no implementations whitelisted.
     */
    function maxVersion() external view returns (uint256);

    /**
     * @notice Whitelist a new implementation for entities.
     * @param entityImplementation address of the new implementation
     */
    function whitelist(address entityImplementation) external;

    /**
     * @notice Migrate a given entity to the next version.
     * @param entity address of the entity to migrate
     * @param data some data to reinitialize the contract with
     */
    function migrate(address entity, bytes memory data) external;

    /**
     * @notice Create a new entity at the registry.
     * @param version entity's version to use
     * @param data initial data for the entity creation
     * @return address of the entity
     */
    function create(uint256 version, bytes memory data) external returns (address);
}

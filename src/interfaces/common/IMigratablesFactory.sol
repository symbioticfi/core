// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRegistry} from "./IRegistry.sol";

/**
 * @title IMigratablesFactory
 * @notice Interface for the MigratablesFactory contract.
 */
interface IMigratablesFactory is IRegistry {
    error AlreadyBlacklisted();
    error AlreadyWhitelisted();
    error InvalidImplementation();
    error InvalidVersion();
    error NotOwner();
    error OldVersion();

    /**
     * @notice Emitted when a new implementation is whitelisted.
     * @param implementation Address of the new implementation.
     */
    event Whitelist(address indexed implementation);

    /**
     * @notice Emitted when a version is blacklisted (e.g., in case of invalid implementation).
     * @param version Version that was blacklisted.
     * @dev The given version is still deployable.
     */
    event Blacklist(uint64 indexed version);

    /**
     * @notice Emitted when an entity is migrated to a new version.
     * @param entity Address of the entity.
     * @param newVersion New version of the entity.
     */
    event Migrate(address indexed entity, uint64 newVersion);

    /**
     * @notice Get if a version is blacklisted (e.g., in case of invalid implementation).
     * @param version Version to check.
     * @return Whether The version is blacklisted.
     * @dev The given version is still deployable.
     */
    function blacklisted(uint64 version) external view returns (bool);

    /**
     * @notice Get the last available version.
     * @return Version Of the last implementation.
     * @dev If zero, no implementations are whitelisted.
     */
    function lastVersion() external view returns (uint64);

    /**
     * @notice Get the implementation for a given version.
     * @param version Version to get the implementation for.
     * @return Address Of the implementation.
     * @dev Reverts when an invalid version.
     */
    function implementation(uint64 version) external view returns (address);

    /**
     * @notice Whitelist a new implementation for entities.
     * @param implementation Address of the new implementation.
     */
    function whitelist(address implementation) external;

    /**
     * @notice Blacklist a version of entities.
     * @param version Version to blacklist.
     * @dev The given version will still be deployable.
     */
    function blacklist(uint64 version) external;

    /**
     * @notice Create a new entity at the factory.
     * @param version Entity's version to use.
     * @param owner Initial owner of the entity.
     * @param data Initial data for the entity creation.
     * @return Address Of the entity.
     * @dev CREATE2 salt is constructed from the given parameters.
     */
    function create(uint64 version, address owner, bytes calldata data) external returns (address);

    /**
     * @notice Migrate a given entity to a given newer version.
     * @param entity Address of the entity to migrate.
     * @param newVersion New version to migrate to.
     * @param data Some data to reinitialize the contract with.
     * @dev Only the entity's owner can call this function.
     */
    function migrate(address entity, uint64 newVersion, bytes calldata data) external;
}

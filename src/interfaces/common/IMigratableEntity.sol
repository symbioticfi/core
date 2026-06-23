// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMigratableEntity
 * @notice Interface for the MigratableEntity contract.
 */
interface IMigratableEntity {
    error AlreadyInitialized();
    error NotFactory();

    /**
     * @notice Get the factory's address.
     * @return Address Of the factory.
     */
    function FACTORY() external view returns (address);

    /**
     * @notice Get the entity's version.
     * @return Version Of the entity.
     * @dev Starts from 1.
     */
    function version() external view returns (uint64);

    /**
     * @notice Initialize this entity contract by using a given data and setting a particular version and owner.
     * @param initialVersion Initial version of the entity.
     * @param owner Initial owner of the entity.
     * @param data Some data to use.
     */
    function initialize(uint64 initialVersion, address owner, bytes calldata data) external;

    /**
     * @notice Migrate this entity to a particular newer version using a given data.
     * @param newVersion New version of the entity.
     * @param data Some data to use.
     */
    function migrate(uint64 newVersion, bytes calldata data) external;
}

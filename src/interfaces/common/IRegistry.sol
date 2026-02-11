// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IRegistry
 * @notice Interface for the Registry contract.
 */
interface IRegistry {
    error EntityNotExist();

    /**
     * @notice Emitted when an entity is added.
     * @param entity Address of the added entity.
     */
    event AddEntity(address indexed entity);

    /**
     * @notice Get if a given address is an entity.
     * @param account Address to check.
     * @return If The given address is an entity.
     */
    function isEntity(address account) external view returns (bool);

    /**
     * @notice Get a total number of entities.
     * @return Total Number of entities added.
     */
    function totalEntities() external view returns (uint256);

    /**
     * @notice Get an entity given its index.
     * @param index Index of the entity to get.
     * @return Address Of the entity.
     */
    function entity(uint256 index) external view returns (address);
}

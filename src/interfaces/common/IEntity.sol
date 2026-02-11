// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEntity
 * @notice Interface for the Entity contract.
 */
interface IEntity {
    error NotInitialized();

    /**
     * @notice Get the factory's address.
     * @return Address Of the factory.
     */
    function FACTORY() external view returns (address);

    /**
     * @notice Get the entity's type.
     * @return Type Of the entity.
     */
    function TYPE() external view returns (uint64);

    /**
     * @notice Initialize this entity contract by using a given data.
     * @param data Some data to use.
     */
    function initialize(bytes calldata data) external;
}

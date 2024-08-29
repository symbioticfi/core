// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IEntity {
    /**
     * @notice Get the factory's address.
     * @return address of the factory
     */
    function FACTORY() external view returns (address);

    /**
     * @notice Get the entity's type.
     * @return type of the entity
     */
    function TYPE() external view returns (uint64);

    /**
     * @notice Get if the entity is initialized.
     * @return if the entity is initialized
     */
    function isInitialized() external view returns (bool);

    /**
     * @notice Initialize this entity contract by using a given data.
     * @param data some data to use
     */
    function initialize(
        bytes calldata data
    ) external;
}

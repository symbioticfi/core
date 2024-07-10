// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IRegistry} from "./IRegistry.sol";

interface IFactory is IRegistry {
    error AlreadyWhitelisted();
    error InvalidImplementation();

    /**
     * @notice Get the total number of whitelisted types.
     * @return total number of types
     */
    function totalTypes() external view returns (uint64);

    /**
     * @notice Get the implementation for a given type.
     * @param type_ position to get the implementation at
     * @return address of the implementation
     */
    function implementation(uint64 type_) external view returns (address);

    /**
     * @notice Whitelist a new type of entities.
     * @param implementation address of the new implementation
     */
    function whitelist(address implementation) external;

    /**
     * @notice Create a new entity at the factory.
     * @param type_ type's implementation to use
     * @param withInitialize whether to call initialize on the entity
     * @param data initial data for the entity creation
     * @return address of the entity
     */
    function create(uint64 type_, bool withInitialize, bytes memory data) external returns (address);
}

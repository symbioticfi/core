// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRegistry} from "./common/IRegistry.sol";

/**
 * @title IAdapterRegistry
 * @notice Interface for the adapter factory registry contract.
 */
interface IAdapterRegistry is IRegistry {
    /**
     * @notice Raised when trying to whitelist an adapter factory that is already whitelisted.
     */
    error AdapterFactoryAlreadyWhitelisted();

    /**
     * @notice Whitelist an adapter factory contract.
     * @param adapterFactory Address of the adapter factory to whitelist.
     * @dev Only the contract owner can call this function.
     */
    function whitelistAdapterFactory(address adapterFactory) external;
}

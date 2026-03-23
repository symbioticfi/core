// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRegistry} from "./common/IRegistry.sol";

/**
 * @title IAdapterRegistry
 * @notice Interface for the AdapterRegistry contract.
 */
interface IAdapterRegistry is IRegistry {
    /**
     * @notice Raised when trying to whitelist a adapter that is already whitelisted.
     */
    error AdapterAlreadyWhitelisted();

    /**
     * @notice Whitelist a adapter contract.
     * @param adapter Address of the adapter to whitelist.
     * @dev Only the contract owner can call this function.
     */
    function whitelistAdapter(address adapter) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAdapterRegistry
 * @notice Interface for the adapter factory registry contract.
 */
interface IAdapterRegistry {
    /**
     * @notice Emitted when an adapter factory is whitelisted for a vault.
     * @param vault Vault address.
     * @param adapterFactory Adapter factory address.
     */
    event Whitelist(address indexed vault, address indexed adapterFactory);

    /**
     * @notice Whitelist an adapter factory contract for a vault.
     * @param vault Vault address.
     * @param adapterFactory Address of the adapter factory to whitelist.
     * @dev Only the contract owner can call this function.
     */
    function whitelist(address vault, address adapterFactory) external;

    /**
     * @notice Check whether an adapter factory is whitelisted.
     * @param vault Vault or delegator context.
     * @param adapterFactory Adapter factory address.
     * @return status Whether the adapter factory is whitelisted.
     */
    function isWhitelisted(address vault, address adapterFactory) external view returns (bool status);
}

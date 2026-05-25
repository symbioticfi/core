// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAdapterRegistry
 * @notice Interface for the adapter factory registry contract.
 */
interface IAdapterRegistry {
    /* EVENTS */

    /**
     * @notice Emitted when a global adapter factory whitelist status is set.
     * @param adapter Adapter factory address.
     * @param status Whether the adapter factory is whitelisted.
     */
    event SetGlobalWhitelistStatus(address indexed adapter, bool status);

    /**
     * @notice Emitted when a vault-specific adapter factory whitelist status is set.
     * @param vault Vault address.
     * @param adapter Adapter factory address.
     * @param status Whether the adapter factory is whitelisted.
     */
    event SetVaultWhitelistStatus(address indexed vault, address indexed adapter, bool status);

    /* FUNCTIONS */

    /**
     * @notice Set a global adapter factory whitelist status.
     * @param adapter Address of the adapter factory.
     * @param status Whether the adapter factory is whitelisted.
     * @dev Only the contract owner can call this function.
     */
    function setGlobalWhitelistStatus(address adapter, bool status) external;

    /**
     * @notice Set a vault-specific adapter factory whitelist status.
     * @param vault Vault address.
     * @param adapter Address of the adapter factory.
     * @param status Whether the adapter factory is whitelisted.
     * @dev Only the contract owner can call this function.
     */
    function setVaultWhitelistStatus(address vault, address adapter, bool status) external;

    /**
     * @notice Check whether an adapter factory is globally whitelisted.
     * @param adapter Adapter factory address.
     * @return status Whether the adapter factory is globally whitelisted.
     */
    function globalIsWhitelisted(address adapter) external view returns (bool status);

    /**
     * @notice Check whether an adapter factory is whitelisted for a vault.
     * @param vault Vault address.
     * @param adapter Adapter factory address.
     * @return status Whether the adapter factory is whitelisted for the vault.
     */
    function vaultIsWhitelisted(address vault, address adapter) external view returns (bool status);

    /**
     * @notice Check whether an adapter factory is whitelisted.
     * @param vault Vault address.
     * @param adapter Adapter factory address.
     * @return status Whether the adapter factory is whitelisted.
     */
    function isWhitelisted(address vault, address adapter) external view returns (bool status);
}

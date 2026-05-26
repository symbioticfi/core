// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAdapterRegistry
 * @notice Interface for the adapter factory registry contract.
 */
interface IAdapterRegistry {
    /* EVENTS */

    /**
     * @notice Emitted when a vault-specific adapter whitelist status is set.
     * @param vault Vault address.
     * @param adapter Adapter address.
     * @param status Whether the adapter is whitelisted for the vault.
     */
    event SetWhitelistedStatus(address indexed vault, address indexed adapter, bool status);

    /* FUNCTIONS */

    /**
     * @notice Set a vault-specific adapter whitelist status.
     * @param vault Vault address.
     * @param adapter Adapter address.
     * @param status Whether the adapter is whitelisted for the vault.
     * @dev Only the contract owner can call this function.
     */
    function setWhitelistedStatus(address vault, address adapter, bool status) external;

    /**
     * @notice Check whether an adapter is whitelisted for a vault.
     * @param vault Vault address.
     * @param adapter Adapter address.
     * @return status Whether the adapter is whitelisted for the vault.
     */
    function isWhitelisted(address vault, address adapter) external view returns (bool status);
}

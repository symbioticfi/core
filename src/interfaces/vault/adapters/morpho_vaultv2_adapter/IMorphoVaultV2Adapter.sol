// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "../../IAdapter.sol";

/**
 * @title IMorphoVaultV2Adapter
 * @notice Interface for the Morpho Vault V2 adapter.
 */
interface IMorphoVaultV2Adapter is IAdapter {
    /* ERRORS */

    /**
     * @notice Raised when trying to replace a Morpho vault while a position is still active.
     */
    error ActivePosition();

    /**
     * @notice Raised when the provided Morpho vault does not match the vault collateral.
     */
    error InvalidMorphoVault();

    /* EVENTS */

    /**
     * @notice Emitted when the adapter deploys a deterministic account for a vault.
     * @param vault Vault address.
     * @param account Deterministic account address.
     */
    event DeployAccount(address indexed vault, address indexed account);

    /**
     * @notice Emitted when a Morpho vault is configured for a vault.
     * @param vault Vault address.
     * @param morphoVault Morpho vault address.
     */
    event SetMorphoVault(address indexed vault, address indexed morphoVault);

    /* FUNCTIONS */

    /**
     * @notice Returns the configured Morpho vault for a vault.
     * @param vault Vault address.
     * @return Configured Morpho vault.
     */
    function morphoVaults(address vault) external view returns (address);

    /**
     * @notice Returns the deterministic account used to hold a vault's Morpho position.
     * @param vault Vault address.
     * @return account Deterministic account address.
     */
    function getAccount(address vault) external view returns (address account);

    /**
     * @notice Returns the vault's live claim on the configured Morpho vault.
     * @param vault Vault address.
     * @return assets Vault assets represented in collateral units.
     */
    function getAssets(address vault) external view returns (uint256 assets);

    /**
     * @notice Sets the Morpho vault for a vault.
     * @param vault Vault address.
     * @param morphoVault Morpho vault address.
     * @dev `morphoVault == address(0)` clears the configured vault.
     */
    function setMorphoVault(address vault, address morphoVault) external;
}

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
     * @notice Returns the total adapter share supply tracked for a Morpho vault.
     * @param morphoVault Morpho vault address.
     * @return Total tracked shares.
     */
    function totalVaultShares(address morphoVault) external view returns (uint256);

    /**
     * @notice Returns the tracked shares of a vault for a Morpho vault.
     * @param morphoVault Morpho vault address.
     * @param vault Vault address.
     * @return Tracked vault shares.
     */
    function vaultShares(address morphoVault, address vault) external view returns (uint256);

    /**
     * @notice Sets the Morpho vault for a vault.
     * @param vault Vault address.
     * @param morphoVault Morpho vault address.
     * @dev `morphoVault == address(0)` clears the configured vault.
     */
    function setMorphoVault(address vault, address morphoVault) external;
}

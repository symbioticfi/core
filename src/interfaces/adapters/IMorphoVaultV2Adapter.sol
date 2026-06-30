// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

/**
 * @title IMorphoVaultV2Adapter
 * @notice Interface for the Morpho Vault V2 adapter.
 */
interface IMorphoVaultV2Adapter is IAdapter {
    /* ERRORS */

    /**
     * @notice Raised when the provided amount is insufficient for the requested operation.
     */
    error InsufficientAmount();

    /**
     * @notice Raised when the provided Morpho vault does not match the vault asset.
     */
    error InvalidMorphoVault();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the Morpho Vault V2 adapter.
     * @param morphoVault Morpho vault address.
     * @param converters Initial converters exempt from the prepared-request delay.
     */
    struct InitParams {
        address morphoVault;
        address[] converters;
    }

    /**
     * @notice Raised when the deposit helper is called directly instead of through the adapter self-call.
     */
    error NotSelf();

    /**
     * @notice Emitted when the adapter is initialized.
     * @param morphoVault Morpho vault address.
     */
    event Initialize(address indexed morphoVault);

    /* FUNCTIONS */

    /**
     * @notice Returns the configured Morpho vault for a vault.
     * @return Configured Morpho vault.
     */
    function morphoVault() external view returns (address);

    /**
     * @notice Returns the adapter-managed Morpho vault shares.
     * @return totalShares Adapter-managed Morpho vault shares.
     */
    function totalShares() external view returns (uint256);
}

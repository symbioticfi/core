// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

// Maximum tolerated loss in smallest units for normal deallocation before force deallocation is required.
uint256 constant DEALLOCATE_BUFFER = 1000;

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
     * @notice Raised when the provided amount is insufficient for the requested operation.
     */
    error InsufficientAmount();

    /**
     * @notice Raised when the provided Morpho vault does not match the vault collateral.
     */
    error InvalidMorphoVault();

    /**
     * @notice Raised when the deposit helper is called directly instead of through the adapter self-call.
     */
    error NotSelf();

    /**
     * @notice Emitted when a curator force-deallocates funds for a vault.
     * @param amount Requested amount to deallocate.
     * @param deallocated Actual amount deallocated.
     */
    event ForceDeallocate(uint256 amount, uint256 deallocated);

    /**
     * @notice Emitted when a Morpho vault is configured for a vault.
     * @param morphoVault Morpho vault address.
     */
    event SetMorphoVault(address indexed morphoVault);

    /* FUNCTIONS */

    /**
     * @notice Returns the configured Morpho vault for a vault.
     * @return Configured Morpho vault.
     */
    function morphoVault() external view returns (address);

    /**
     * @notice Force-deallocates collateral for a vault.
     * @param amount Requested amount to deallocate.
     * @return deallocated Actual amount deallocated.
     */
    function forceDeallocate(uint256 amount) external returns (uint256 deallocated);

    /**
     * @notice Sets the Morpho vault for a vault.
     * @param morphoVault Morpho vault address.
     * @dev `morphoVault == address(0)` clears the configured vault.
     */
    function setMorphoVault(address morphoVault) external;
}

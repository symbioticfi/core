// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

/**
 * @title IEulerAdapter
 * @notice Interface for the Euler Lend adapter.
 */
interface IEulerAdapter is IAdapter {
    /* ERRORS */

    /**
     * @notice Raised when the provided amount is insufficient for the requested operation.
     */
    error InsufficientAmount();

    /**
     * @notice Raised when the provided Euler Lend vault does not match the vault asset.
     */
    error InvalidEulerLendVault();

    /**
     * @notice Raised when the lend helper is called directly instead of through the adapter self-call.
     */
    error NotSelf();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the Euler adapter.
     * @param lendVault Euler Lend vault address.
     * @param converters Initial converters exempt from the prepared-request delay.
     */
    struct InitParams {
        address lendVault;
        address[] converters;
    }

    /* EVENTS */

    /**
     * @notice Emitted when the adapter is initialized.
     * @param lendVault Euler Lend vault address.
     */
    event Initialize(address indexed lendVault);

    /* FUNCTIONS */

    /**
     * @notice Returns the configured Euler Lend vault.
     * @return lendVault Euler Lend vault address.
     */
    function lendVault() external view returns (address lendVault);

    /**
     * @notice Returns the adapter-managed Euler Lend vault shares.
     * @return totalShares Adapter-managed Euler Lend vault shares.
     */
    function totalShares() external view returns (uint256 totalShares);
}

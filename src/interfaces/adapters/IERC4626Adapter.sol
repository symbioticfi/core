// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

/**
 * @title IERC4626Adapter
 * @notice Interface for the ERC4626 vault adapter.
 */
interface IERC4626Adapter is IAdapter {
    /* ERRORS */

    /**
     * @notice Raised when the provided amount is insufficient for the requested operation.
     */
    error InsufficientAmount();

    /**
     * @notice Raised when the provided ERC4626 vault does not match the vault asset.
     */
    error InvalidERC4626Vault();

    /**
     * @notice Raised when the deposit helper is called directly instead of through the adapter self-call.
     */
    error NotSelf();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the ERC4626 adapter.
     * @param converters Initial converters exempt from the prepared-request delay.
     * @param erc4626Vault ERC4626 vault address.
     */
    struct InitParams {
        address[] converters;
        address erc4626Vault;
    }

    /* EVENTS */

    /**
     * @notice Emitted when the adapter is initialized.
     * @param erc4626Vault ERC4626 vault address.
     */
    event Initialize(address indexed erc4626Vault);

    /* FUNCTIONS */

    /**
     * @notice Returns the configured ERC4626 vault.
     * @return erc4626Vault Configured ERC4626 vault.
     */
    function erc4626Vault() external view returns (address erc4626Vault);

    /**
     * @notice Deposits assets into the configured ERC4626 vault.
     * @param amount Asset amount to deposit.
     */
    function deposit(uint256 amount) external;
}

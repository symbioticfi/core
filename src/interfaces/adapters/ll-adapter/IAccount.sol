// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICoWSwapConverter} from "../common/ICoWSwapConverter.sol";

/**
 * @title IAccount
 * @notice Interface for token-specific liquidity lane accounts.
 */
interface IAccount is ICoWSwapConverter {
    /* ERRORS */

    /**
     * @notice Raised when the account oracle returns zero.
     */
    error InvalidOracle();

    /**
     * @notice Raised when the caller is not the bound adapter.
     */
    error NotAdapter();

    /* FUNCTIONS */

    /**
     * @notice Returns the token submitted through this account.
     * @return tokenToRedeem The token-to-redeem address.
     */
    function TOKEN_TO_REDEEM() external view returns (address tokenToRedeem);

    /**
     * @notice Returns the oracle used to price the token-to-redeem.
     * @return oracle The oracle address.
     */
    function ORACLE() external view returns (address oracle);

    /**
     * @notice Returns the adapter bound to the account.
     * @return adapter The adapter address.
     */
    function adapter() external view returns (address adapter);

    /**
     * @notice Returns the vault bound to the account.
     * @return vault The vault address.
     */
    function vault() external view returns (address vault);

    /**
     * @notice Returns the account's current vault-asset value.
     * @return assets The current vault-asset value.
     */
    function totalAssets() external view returns (uint256 assets);

    /**
     * @notice Synchronizes held token-to-redeem inventory and pending issuer state. Permissionless housekeeping.
     * @dev Realized proceeds stay as the account's vault-asset balance, approved to the adapter for `transferFrom`.
     */
    function sync() external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISettlementSubAccount
 * @notice Interface for request-holder subaccounts of one issuer redemption.
 */
interface ISettlementSubAccount {
    /* ERRORS */

    /**
     * @notice Raised when a caller is not the parent account.
     */
    error NotAccount();

    /* FUNCTIONS */

    /**
     * @notice Requests redemption of held tokens through the issuer.
     */
    function requestRedeem() external;

    /**
     * @notice Sweeps received settlement assets and returned tokens to the parent account.
     * @return assets The vault-asset amount swept.
     * @return tokenAmount The token-to-redeem amount swept.
     */
    function sync() external returns (uint256 assets, uint256 tokenAmount);
}

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
     */
    function sync() external;

    /**
     * @notice Returns whether settlement assets have been received.
     * @return status True if the settlement batch arrived.
     */
    function isSettled() external view returns (bool status);
}

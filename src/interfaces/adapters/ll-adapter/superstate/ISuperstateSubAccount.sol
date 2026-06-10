// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISuperstateSubAccount
 * @notice Interface for Superstate request-holder subaccounts.
 */
interface ISuperstateSubAccount {
    /* ERRORS */

    /**
     * @notice Raised when a caller is not the parent account.
     */
    error NotAccount();

    /* FUNCTIONS */

    /**
     * @notice Requests redemption of held Superstate tokens.
     */
    function requestRedeem() external;

    /**
     * @notice Forwards returned vault assets to the parent account.
     */
    function sync() external;

    /**
     * @notice Returns whether the request has no pending or held settlement assets.
     * @return status True if the request is settled.
     */
    function isSettled() external view returns (bool status);

    /**
     * @notice Returns the subaccount's pending and held vault-asset value.
     * @return assets The pending and held vault-asset value.
     */
    function totalAssets() external view returns (uint256 assets);
}

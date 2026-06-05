// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IGaibSubAccount
 * @notice Interface for GAIB request-holder subaccounts.
 */
interface IGaibSubAccount {
    /* ERRORS */

    /**
     * @notice Raised when a caller is not the parent account.
     */
    error NotAccount();

    /* FUNCTIONS */

    /**
     * @notice Submits held sAID for queued unstaking.
     * @param amount The sAID amount to unstake.
     */
    function requestRedeem(uint256 amount) external;

    /**
     * @notice Processes the subaccount queue item and forwards claimed AID to the parent account.
     */
    function sync() external;

    /**
     * @notice Returns the subaccount's pending and held AID value.
     * @return assets The pending and held AID value.
     */
    function totalAssets() external view returns (uint256 assets);
}

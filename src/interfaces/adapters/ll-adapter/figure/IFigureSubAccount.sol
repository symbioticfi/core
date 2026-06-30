// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IFigureSubAccount
 * @notice Interface for Figure request-holder subaccounts.
 */
interface IFigureSubAccount {
    /* ERRORS */

    /**
     * @notice Raised when a caller is not the parent account.
     */
    error NotAccount();

    /* FUNCTIONS */

    /**
     * @notice Submits held wYLDS for queued redemption.
     */
    function requestRedeem() external;

    /**
     * @notice Forwards settled redemption assets to the parent account.
     */
    function finalizeRedeem() external;
}

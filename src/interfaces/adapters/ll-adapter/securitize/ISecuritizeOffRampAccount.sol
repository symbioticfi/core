// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "../IAccount.sol";

/**
 * @title ISecuritizeOffRampAccount
 * @notice Interface for synchronous Securitize off-ramp accounts.
 */
interface ISecuritizeOffRampAccount is IAccount {
    /* ERRORS */

    /**
     * @notice Raised when the off-ramp delivers less than its accepted quote.
     * @param received The observed vault-asset balance increase.
     * @param expected The accepted off-ramp quote.
     */
    error InsufficientOutput(uint256 received, uint256 expected);

    /**
     * @notice Raised when the off-ramp quote is below the independent oracle value.
     * @param quote The off-ramp's post-fee quote.
     * @param expected The independent oracle value.
     */
    error InsufficientQuote(uint256 quote, uint256 expected);

    /**
     * @notice Raised when the vault asset or current off-ramp output token is invalid.
     */
    error InvalidAsset();

    /**
     * @notice Raised when the current off-ramp input token is invalid.
     */
    error InvalidTokenToRedeem();

    /* FUNCTIONS */

    /**
     * @notice Returns the Securitize off-ramp.
     * @return offRamp The off-ramp address.
     */
    function OFF_RAMP() external view returns (address offRamp);

    /**
     * @notice Returns the off-ramp output token required as the vault asset.
     * @return redemptionToken The redemption-token address.
     */
    function REDEMPTION_TOKEN() external view returns (address redemptionToken);
}

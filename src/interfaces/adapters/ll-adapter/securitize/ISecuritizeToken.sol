// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISecuritizeToken
 * @notice Interface for Securitize token burn redemptions.
 */
interface ISecuritizeToken {
    /* FUNCTIONS */

    /**
     * @notice Burns tokens as a redemption request.
     * @param account The token holder.
     * @param amount The token amount.
     * @param reason The burn reason.
     */
    function burn(address account, uint256 amount, string calldata reason) external;
}

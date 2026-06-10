// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISuperstateToken
 * @notice Interface for Superstate off-chain redemption requests.
 */
interface ISuperstateToken {
    /* FUNCTIONS */

    /**
     * @notice Burns tokens and submits an off-chain redemption request.
     * @param amount The token amount.
     */
    function offchainRedeem(uint256 amount) external;
}

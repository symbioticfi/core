// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IPikuFundingManager
 * @notice Interface for the Piku funding manager redemption queue.
 */
interface IPikuFundingManager {
    /* FUNCTIONS */

    /**
     * @notice Queues a token redemption request.
     * @param depositAmount The token amount to redeem.
     * @param minAmountOut The minimum asset amount expected.
     */
    function sell(uint256 depositAmount, uint256 minAmountOut) external;

    /**
     * @notice Claims processed redemption assets.
     */
    function claim() external;
}

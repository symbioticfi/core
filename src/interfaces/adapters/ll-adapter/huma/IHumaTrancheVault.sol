// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IHumaTrancheVault
 * @notice Minimal Huma tranche vault interface used by liquidity lane accounts.
 */
interface IHumaTrancheVault {
    /* FUNCTIONS */

    /**
     * @notice Submits shares for redemption processing.
     * @param shares The share amount.
     */
    function addRedemptionRequest(uint256 shares) external;

    /**
     * @notice Withdraws fulfilled redemption proceeds.
     */
    function disburse() external;

    /**
     * @notice Withdraws funds after pool closure.
     */
    function withdrawAfterPoolClosure() external;
}

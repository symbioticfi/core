// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISaid
 * @notice Interface for GAIB sAID withdrawal queue operations.
 */
interface ISaid {
    /* FUNCTIONS */

    /**
     * @notice Returns shares converted to AID at the loss-aware unstaking NAV.
     * @param shares The sAID share amount.
     * @return assets The AID asset amount.
     */
    function convertToAssetsWithLoss(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Returns the active unstake request for a user.
     * @param user The request owner.
     * @return requestTime The request timestamp.
     * @return pendingAssets The pending AID amount.
     */
    function getUnstakeRequest(address user) external view returns (uint256 requestTime, uint256 pendingAssets);

    /**
     * @notice Processes queued unstake requests.
     * @param maxIterations The maximum number of queue items to process.
     */
    function processUnstakeQueue(uint256 maxIterations) external;

    /**
     * @notice Submits sAID shares for queued unstaking.
     * @param shares The sAID share amount.
     */
    function unstake(uint256 shares) external;
}

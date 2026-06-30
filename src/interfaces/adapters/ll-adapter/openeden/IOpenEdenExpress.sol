// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IOpenEdenExpress
 * @notice Interface for OpenEden HYBONDExpress redemptions.
 */
interface IOpenEdenExpress {
    /* FUNCTIONS */

    /**
     * @notice Returns the account's HYBOND amount in the pending redeem queue.
     * @param account The receiver account.
     * @return amount The pending HYBOND amount.
     */
    function pendingRedeemInfo(address account) external view returns (uint256 amount);

    /**
     * @notice Returns the account's HYBOND amount in the final redeem queue.
     * @param account The receiver account.
     * @return amount The final-queue HYBOND amount.
     */
    function redeemInfo(address account) external view returns (uint256 amount);

    /**
     * @notice Previews a HYBOND redemption in the current redeem asset.
     * @param tokenAmount The HYBOND amount.
     * @return feeAmt The fee amount in redeem asset units.
     * @return redeemAssetAmt The gross redeem asset amount.
     * @return netRedeemAssetAmt The net redeem asset amount.
     */
    function previewRedeem(uint256 tokenAmount)
        external
        view
        returns (uint256 feeAmt, uint256 redeemAssetAmt, uint256 netRedeemAssetAmt);

    /**
     * @notice Returns the HYBOND redeem asset.
     * @return asset The redeem asset address.
     */
    function redeemAsset() external view returns (address asset);

    /**
     * @notice Requests HYBOND redemption for a receiver.
     * @param to The redemption receiver.
     * @param tokenAmount The HYBOND amount.
     */
    function requestRedeem(address to, uint256 tokenAmount) external;
}

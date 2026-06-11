// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IFigureYieldVault
 * @notice Minimal Figure/Hastra yield vault interface used by liquidity lane accounts.
 */
interface IFigureYieldVault {
    /* FUNCTIONS */

    /**
     * @notice Returns the vault asset.
     * @return asset The asset address.
     */
    function asset() external view returns (address asset);

    /**
     * @notice Converts shares to assets.
     * @param shares The share amount.
     * @return assets The asset amount.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Returns the pending redemption for a user.
     * @param user The user address.
     * @return shares The pending share amount.
     * @return assets The pending asset amount.
     * @return timestamp The request timestamp.
     */
    function pendingRedemptions(address user)
        external
        view
        returns (uint256 shares, uint256 assets, uint256 timestamp);

    /**
     * @notice Requests redemption for held shares.
     * @param shares The share amount.
     */
    function requestRedeem(uint256 shares) external;
}

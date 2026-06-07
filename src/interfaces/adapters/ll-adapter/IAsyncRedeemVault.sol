// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAsyncRedeemVault
 * @notice Minimal ERC-7540 async redeem vault interface used by liquidity lane accounts.
 */
interface IAsyncRedeemVault {
    /* FUNCTIONS */

    /**
     * @notice Converts shares to assets.
     * @param shares The share amount.
     * @return assets The asset amount.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Previews withdrawn assets for shares.
     * @param shares The share amount.
     * @return assets The asset amount.
     */
    function previewWithdraw(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Returns pending redemption shares for a request.
     * @param requestId The request id.
     * @param controller The request controller.
     * @return shares The pending shares.
     */
    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256 shares);

    /**
     * @notice Returns claimable redemption shares for a request.
     * @param requestId The request id.
     * @param controller The request controller.
     * @return shares The claimable shares.
     */
    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256 shares);

    /**
     * @notice Requests an async redemption.
     * @param shares The share amount.
     * @param controller The request controller.
     * @param owner The share owner.
     * @return requestId The created request id.
     */
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    /**
     * @notice Claims a processed async redemption.
     * @param shares The shares to claim.
     * @param receiver The asset receiver.
     * @param controller The request controller.
     * @return assets The claimed asset amount.
     */
    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);
}

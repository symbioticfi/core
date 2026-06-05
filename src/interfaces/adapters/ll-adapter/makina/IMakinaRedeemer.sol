// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMakinaRedeemer
 * @notice Interface for Makina async redeemer receipt flows.
 */
interface IMakinaRedeemer {
    /* FUNCTIONS */

    /**
     * @notice Returns the Makina Machine backing the redeemer.
     * @return machine The Machine address.
     */
    function machine() external view returns (address machine);

    /**
     * @notice Returns the shares held by a redemption receipt.
     * @param requestId The redemption receipt id.
     * @return shares The queued share amount.
     */
    function getShares(uint256 requestId) external view returns (uint256 shares);

    /**
     * @notice Returns assets claimable by a finalized redemption receipt.
     * @param requestId The redemption receipt id.
     * @return assets The claimable asset amount.
     */
    function getClaimableAssets(uint256 requestId) external view returns (uint256 assets);

    /**
     * @notice Creates a redemption request and mints a receipt NFT to the receiver.
     * @param shares The share amount to redeem.
     * @param receiver The receipt receiver.
     * @param minAssets The minimum accepted asset amount.
     * @return requestId The created request id.
     */
    function requestRedeem(uint256 shares, address receiver, uint256 minAssets) external returns (uint256 requestId);

    /**
     * @notice Claims finalized redemption assets and burns the receipt NFT.
     * @param requestId The redemption receipt id.
     * @return assets The claimed asset amount.
     */
    function claimAssets(uint256 requestId) external returns (uint256 assets);
}

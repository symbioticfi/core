// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IThreeFVaultController
 * @notice Minimal interface for 3F request vault redemption.
 */
interface IThreeFVaultController {
    /**
     * @notice Returns whether redemption is available.
     * @return status Whether redemption is available.
     */
    function canWithdraw() external view returns (bool status);

    /**
     * @notice Returns principal and yield token balances for an account.
     * @param account Account to query.
     * @return ptShares Principal token shares.
     * @return ytShares Yield token shares.
     */
    function balancesOf(address account) external view returns (uint256 ptShares, uint256 ytShares);

    /**
     * @notice Converts principal and yield shares into current request assets.
     * @param ptShares Principal token shares.
     * @param ytShares Yield token shares.
     * @return pAssets Principal assets.
     * @return yAssets Yield assets.
     */
    function convertToAssets(uint256 ptShares, uint256 ytShares)
        external
        view
        returns (uint256 pAssets, uint256 yAssets);

    /**
     * @notice Burns all principal and yield shares owned by an account.
     * @param owner Account whose shares are burned.
     * @param receiver Asset receiver.
     * @return ptShares Burned principal token shares.
     * @return ytShares Burned yield token shares.
     * @return pAssets Redeemed principal assets.
     * @return yAssets Redeemed yield assets.
     */
    function burnAll(address owner, address receiver)
        external
        returns (uint256 ptShares, uint256 ytShares, uint256 pAssets, uint256 yAssets);
}

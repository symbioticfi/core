// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";

/**
 * @title ERC4626Math
 * @notice Library implementing an ERC4626 share-and-asset conversion helper set.
 */
library ERC4626Math {
    using Math for uint256;

    /**
     * @notice Preview the number of shares minted for a deposit of assets.
     * @param assets The amount of assets being deposited.
     * @param totalShares The current total supply of shares.
     * @param totalAssets The current total amount of managed assets.
     * @return shares The number of shares that would be minted.
     */
    function previewDeposit(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256) {
        return assets.fullMulDiv(totalShares + 1, totalAssets + 1);
    }

    /**
     * @notice Preview the amount of assets required to mint shares.
     * @param shares The amount of shares to mint.
     * @param totalAssets The current total amount of managed assets.
     * @param totalShares The current total supply of shares.
     * @return assets The amount of assets that would be required.
     */
    function previewMint(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.fullMulDivUp(totalAssets + 1, totalShares + 1);
    }

    /**
     * @notice Preview the number of shares burned to withdraw assets.
     * @param assets The amount of assets to withdraw.
     * @param totalShares The current total supply of shares.
     * @param totalAssets The current total amount of managed assets.
     * @return shares The number of shares that would be burned.
     */
    function previewWithdraw(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256) {
        return assets.fullMulDivUp(totalShares + 1, totalAssets + 1);
    }

    /**
     * @notice Preview the amount of assets returned for redeemed shares.
     * @param shares The amount of shares to redeem.
     * @param totalAssets The current total amount of managed assets.
     * @param totalShares The current total supply of shares.
     * @return assets The amount of assets that would be returned.
     */
    function previewRedeem(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.fullMulDiv(totalAssets + 1, totalShares + 1);
    }
}

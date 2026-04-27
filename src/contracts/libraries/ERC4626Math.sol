// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ERC4626Math
 * @notice Library implementing an ERC4626 share-and-asset conversion helper set.\
 * @dev DEPRECATED: use vault/common/ERC4626Math.sol instead
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
        return convertToShares(assets, totalShares, totalAssets, Math.Rounding.Floor);
    }

    /**
     * @notice Preview the amount of assets required to mint shares.
     * @param shares The amount of shares to mint.
     * @param totalAssets The current total amount of managed assets.
     * @param totalShares The current total supply of shares.
     * @return assets The amount of assets that would be required.
     */
    function previewMint(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return convertToAssets(shares, totalAssets, totalShares, Math.Rounding.Ceil);
    }

    /**
     * @notice Preview the number of shares burned to withdraw assets.
     * @param assets The amount of assets to withdraw.
     * @param totalShares The current total supply of shares.
     * @param totalAssets The current total amount of managed assets.
     * @return shares The number of shares that would be burned.
     */
    function previewWithdraw(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256) {
        return convertToShares(assets, totalShares, totalAssets, Math.Rounding.Ceil);
    }

    /**
     * @notice Preview the amount of assets returned for redeemed shares.
     * @param shares The amount of shares to redeem.
     * @param totalAssets The current total amount of managed assets.
     * @param totalShares The current total supply of shares.
     * @return assets The amount of assets that would be returned.
     */
    function previewRedeem(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return convertToAssets(shares, totalAssets, totalShares, Math.Rounding.Floor);
    }

    /**
     * @notice Convert an asset amount to shares using the supplied rounding direction.
     * @param assets The amount of assets to convert.
     * @param totalShares The current total supply of shares.
     * @param totalAssets The current total amount of managed assets.
     * @param rounding The rounding direction to apply to the conversion.
     * @return shares The equivalent number of shares.
     */
    function convertToShares(uint256 assets, uint256 totalShares, uint256 totalAssets, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return assets.mulDiv(totalShares + 10 ** _decimalsOffset(), totalAssets + 1, rounding);
    }

    /**
     * @notice Convert a share amount to assets using the supplied rounding direction.
     * @param shares The amount of shares to convert.
     * @param totalAssets The current total amount of managed assets.
     * @param totalShares The current total supply of shares.
     * @param rounding The rounding direction to apply to the conversion.
     * @return assets The equivalent amount of assets.
     */
    function convertToAssets(uint256 shares, uint256 totalAssets, uint256 totalShares, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return shares.mulDiv(totalAssets + 1, totalShares + 10 ** _decimalsOffset(), rounding);
    }

    /**
     * @dev Get the decimal offset used when computing virtual shares.
     * @return decimalsOffset The decimal offset applied to virtual shares.
     */
    function _decimalsOffset() private pure returns (uint8) {
        return 0;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";

/**
 * @title ERC4626Math
 * @notice Contract-library implementing an ERC4626 share-and-asset conversion helper set.
 */
abstract contract ERC4626Math {
    using Math for uint256;

    /**
     * @notice Preview the number of shares minted for a deposit of assets.
     * @param assets The amount of assets being deposited.
     * @param totalShares The current total supply of shares.
     * @param totalAssets The current total amount of managed assets.
     * @return shares The number of shares that would be minted.
     */
    function _previewDeposit(uint256 assets, uint256 totalShares, uint256 totalAssets) internal view returns (uint256) {
        return assets.fullMulDiv(totalShares + _virtualShares(), totalAssets + _virtualAssets());
    }

    /**
     * @notice Preview the amount of assets required to mint shares.
     * @param shares The amount of shares to mint.
     * @param totalAssets The current total amount of managed assets.
     * @param totalShares The current total supply of shares.
     * @return assets The amount of assets that would be required.
     */
    function _previewMint(uint256 shares, uint256 totalAssets, uint256 totalShares) internal view returns (uint256) {
        return shares.fullMulDivUp(totalAssets + _virtualAssets(), totalShares + _virtualShares());
    }

    /**
     * @notice Preview the number of shares burned to withdraw assets.
     * @param assets The amount of assets to withdraw.
     * @param totalShares The current total supply of shares.
     * @param totalAssets The current total amount of managed assets.
     * @return shares The number of shares that would be burned.
     */
    function _previewWithdraw(uint256 assets, uint256 totalShares, uint256 totalAssets)
        internal
        view
        returns (uint256)
    {
        return assets.fullMulDivUp(totalShares + _virtualShares(), totalAssets + _virtualAssets());
    }

    /**
     * @notice Preview the amount of assets returned for redeemed shares.
     * @param shares The amount of shares to redeem.
     * @param totalAssets The current total amount of managed assets.
     * @param totalShares The current total supply of shares.
     * @return assets The amount of assets that would be returned.
     */
    function _previewRedeem(uint256 shares, uint256 totalAssets, uint256 totalShares) internal view returns (uint256) {
        return shares.fullMulDiv(totalAssets + _virtualAssets(), totalShares + _virtualShares());
    }

    function _virtualAssets() internal view returns (uint256) {
        return 1;
    }

    /**
     * @notice Get the virtual shares to use in ERC4626 conversions.
     */
    function _virtualShares() internal view returns (uint256) {
        return 10 ** _decimalsOffset();
    }

    /**
     * @notice Get the decimals offset to apply for virtual shares.
     */
    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }
}

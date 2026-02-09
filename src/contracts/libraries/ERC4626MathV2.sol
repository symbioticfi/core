// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";

/**
 * @dev This library adds helper functions for ERC4626 math operations.
 */
library ERC4626Math {
    using Math for uint256;

    function previewDeposit(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256) {
        return assets.fullMulDiv(totalShares + 1, totalAssets + 1);
    }

    function previewMint(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.fullMulDivUp(totalAssets + 1, totalShares + 1);
    }

    function previewWithdraw(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256) {
        return assets.fullMulDivUp(totalShares + 1, totalAssets + 1);
    }

    function previewRedeem(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.fullMulDiv(totalAssets + 1, totalShares + 1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @dev This library adds helper functions for ERC4626 math operations.
 */
library ERC4626Math {
    using Math for uint256;

    function previewDeposit(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256) {
        return assets.fullMulDivUnchecked(totalShares + 1, totalAssets + 1);
    }

    function previewMint(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        uint256 totalAssetsPlusOne = totalAssets + 1;
        uint256 totalSharesPlusOne = totalShares + 1;
        return shares.fullMulDivUnchecked(totalAssetsPlusOne, totalSharesPlusOne)
            + SafeCast.toUint(mulmod(shares, totalAssetsPlusOne, totalSharesPlusOne) > 0);
    }

    function previewWithdraw(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256) {
        uint256 totalAssetsPlusOne = totalAssets + 1;
        uint256 totalSharesPlusOne = totalShares + 1;
        return assets.fullMulDivUnchecked(totalAssetsPlusOne, totalSharesPlusOne)
            + SafeCast.toUint(mulmod(assets, totalAssetsPlusOne, totalSharesPlusOne) > 0);
    }

    function previewRedeem(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.fullMulDivUnchecked(totalAssets + 1, totalShares + 1);
    }
}

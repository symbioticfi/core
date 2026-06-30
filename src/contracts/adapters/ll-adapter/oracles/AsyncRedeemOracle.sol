// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {IAsyncRedeemOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IAsyncRedeemOracle.sol";
import {IAsyncRedeemVault} from "../../../../interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title AsyncRedeemOracle
/// @notice Oracle returning an ERC-7540 async redeem vault share price in `1e18` precision.
contract AsyncRedeemOracle is Oracle, IAsyncRedeemOracle {
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IAsyncRedeemOracle
    address public immutable ASYNC_REDEEM_VAULT;

    /// @dev Async redeem vault asset unit.
    uint256 internal immutable _assetUnit;
    /// @dev Async redeem vault share unit.
    uint256 internal immutable _shareUnit;

    /* CONSTRUCTOR */

    /// @notice Creates the async redeem vault share-price oracle.
    constructor(uint256 minPrice, uint256 maxPrice, address asyncRedeemVault) Oracle(minPrice, maxPrice) {
        ASYNC_REDEEM_VAULT = asyncRedeemVault;
        _shareUnit = 10 ** IERC20Metadata(asyncRedeemVault).decimals();
        _assetUnit = 10 ** IERC20Metadata(IAsyncRedeemVault(asyncRedeemVault).asset()).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        return IAsyncRedeemVault(ASYNC_REDEEM_VAULT).convertToAssets(_shareUnit).mulDiv(1e18, _assetUnit);
    }
}

// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Oracle} from "./Oracle.sol";

import {IAsyncRedeemOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IAsyncRedeemOracle.sol";
import {IAsyncRedeemVault} from "../../../../interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title AsyncRedeemOracle
/// @notice Oracle returning an ERC-7540 async redeem vault share price in `1e18` precision.
contract AsyncRedeemOracle is Oracle, IAsyncRedeemOracle {
    /* IMMUTABLES */

    /// @inheritdoc IAsyncRedeemOracle
    address public immutable ASYNC_REDEEM_VAULT;

    /// @dev Async redeem vault share unit.
    uint256 internal immutable SHARE_UNIT;
    /// @dev Async redeem vault asset unit.
    uint256 internal immutable ASSET_UNIT;

    /* CONSTRUCTOR */

    /// @notice Creates the async redeem vault share-price oracle.
    constructor(uint256 minPrice, uint256 maxPrice, address tokenToRedeem, address asyncRedeemVault)
        Oracle(minPrice, maxPrice)
    {
        ASYNC_REDEEM_VAULT = asyncRedeemVault;
        SHARE_UNIT = 10 ** IERC20Metadata(tokenToRedeem).decimals();
        ASSET_UNIT = 10 ** IERC20Metadata(IAsyncRedeemVault(asyncRedeemVault).asset()).decimals();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc Oracle
    function _getPrice() internal view override returns (uint256) {
        return IAsyncRedeemVault(ASYNC_REDEEM_VAULT).convertToAssets(SHARE_UNIT) * 1e18 / ASSET_UNIT;
    }
}

// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "./Account.sol";

import {ITheoAccount} from "../../../interfaces/adapters/ll-adapter/theo/ITheoAccount.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title TheoAccount
/// @notice Account for Theo ERC-4626-style redemptions.
contract TheoAccount is Account, ITheoAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Theo account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement, cowSwapVaultRelayer) {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns no additional assets for synchronous Theo redemptions.
    function _totalAssets() internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Redeems held Theo shares into the vault asset.
    function _sync() internal override {
        uint256 shares = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (shares == 0) {
            return;
        }
        IERC4626(TOKEN_TO_REDEEM).redeem(shares, address(this), address(this));
    }
}

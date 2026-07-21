// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ThreeJaneAccount
/// @notice Account for 3Jane USD3 liquidity-limited redemptions.
contract ThreeJaneAccount is Account {
    /* IMMUTABLES */

    /// @notice Native redemption token redeemed from USD3.
    address public immutable REDEMPTION_TOKEN;

    /* CONSTRUCTOR */

    /// @notice Creates the 3Jane USD3 account implementation.
    constructor(address oracle, address factory, address tokenToRedeem, address cowSwapSettlement)
        Account(oracle, factory, tokenToRedeem, cowSwapSettlement)
    {
        REDEMPTION_TOKEN = IERC4626(tokenToRedeem).asset();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns held USDC value not already counted as the vault asset.
    function _totalAssets() internal view override returns (uint256) {
        if (_asset == REDEMPTION_TOKEN) {
            return 0;
        }

        uint256 redemptionTokenBalance = IERC20(REDEMPTION_TOKEN).balanceOf(address(this));
        return redemptionTokenBalance == 0 ? 0 : _redemptionTokenToAssets(REDEMPTION_TOKEN, redemptionTokenBalance);
    }

    /// @dev Natively withdraws available USD3 into USDC up to the vault liquidity.
    function _sync() internal override {
        if (IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)) == 0) {
            return;
        }

        uint256 assets = IERC4626(TOKEN_TO_REDEEM).maxWithdraw(address(this));
        if (assets > 0) {
            IERC4626(TOKEN_TO_REDEEM).withdraw(assets, address(this), address(this));
        }
    }
}

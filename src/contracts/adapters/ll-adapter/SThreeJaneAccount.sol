// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {ISThreeJaneSUSD3} from "../../../interfaces/adapters/ll-adapter/sthreejane/ISThreeJaneSUSD3.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title SThreeJaneAccount
/// @notice Account for 3Jane sUSD3 cooldown redemptions.
contract SThreeJaneAccount is Account {
    /* IMMUTABLES */

    /// @notice USD3 token redeemed from sUSD3.
    address public immutable USD3;
    /// @notice Native redemption token redeemed from USD3.
    address public immutable REDEMPTION_TOKEN;

    /* CONSTRUCTOR */

    /// @notice Creates the 3Jane account implementation.
    constructor(address oracle, address factory, address tokenToRedeem, address cowSwapSettlement)
        Account(oracle, factory, tokenToRedeem, cowSwapSettlement)
    {
        USD3 = IERC4626(tokenToRedeem).asset();
        REDEMPTION_TOKEN = IERC4626(USD3).asset();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns held USD3 and USDC value not already counted as the vault asset.
    function _totalAssets() internal view override returns (uint256) {
        if (_asset == USD3) {
            uint256 redemptionTokenBalance = IERC20(REDEMPTION_TOKEN).balanceOf(address(this));
            return _redemptionTokenToAssets(REDEMPTION_TOKEN, redemptionTokenBalance);
        }

        uint256 usd3Balance = IERC20(USD3).balanceOf(address(this));
        uint256 assets = usd3Balance == 0 ? 0 : IERC4626(USD3).convertToAssets(usd3Balance);
        return _asset == REDEMPTION_TOKEN
            ? assets
            : _redemptionTokenToAssets(REDEMPTION_TOKEN, assets + IERC20(REDEMPTION_TOKEN).balanceOf(address(this)));
    }

    /// @dev Starts or executes the sUSD3 cooldown, then natively withdraws available USD3 into USDC.
    function _sync() internal override {
        uint256 balance = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        uint256 assets;
        if (balance > 0) {
            assets = IERC4626(TOKEN_TO_REDEEM).maxWithdraw(address(this));
            if (assets > 0) {
                balance -= IERC4626(TOKEN_TO_REDEEM).withdraw(assets, address(this), address(this));
            }

            if (balance > 0) {
                (, uint256 windowEnd,) = ISThreeJaneSUSD3(TOKEN_TO_REDEEM).getCooldownStatus(address(this));
                if (block.timestamp > windowEnd) {
                    ISThreeJaneSUSD3(TOKEN_TO_REDEEM).startCooldown(balance);
                }
            }
        }

        if (IERC20(USD3).balanceOf(address(this)) == 0) {
            return;
        }
        assets = IERC4626(USD3).maxWithdraw(address(this));
        if (assets > 0) {
            IERC4626(USD3).withdraw(assets, address(this), address(this));
        }
    }
}

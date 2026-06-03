// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {AsyncRedeemAccount} from "./AsyncRedeemAccount.sol";

import {IFigureAccount} from "../../../interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title FigureAccount
/// @notice Account for Figure/Hastra PRIME redemptions through wYLDS.
contract FigureAccount is AsyncRedeemAccount, IFigureAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Figure account implementation.
    constructor(address asyncRedeemVault, address tokenToRedeem, address redeemShare, address factory, address oracle)
        AsyncRedeemAccount(asyncRedeemVault, tokenToRedeem, redeemShare, factory, oracle)
    {}

    /* INTERNAL FUNCTIONS */

    /// @dev Instantly redeems held PRIME into wYLDS before submitting the wYLDS redemption request.
    function _beforeRequestRedeem() internal override {
        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amountToRedeem == 0) {
            return;
        }
        IERC4626(TOKEN_TO_REDEEM).redeem(amountToRedeem, address(this), address(this));
    }
}

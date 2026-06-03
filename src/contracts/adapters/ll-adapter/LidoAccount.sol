// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "./Account.sol";

import {ILidoAccount} from "../../../interfaces/adapters/ll-adapter/lido/ILidoAccount.sol";
import {IWstETH} from "../../../interfaces/adapters/ll-adapter/lido/IWstETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LidoAccount
/// @notice Account for Lido wstETH redemptions.
contract LidoAccount is Account, ILidoAccount {
    /// @inheritdoc ILidoAccount
    address public immutable STETH;
    /// @inheritdoc ILidoAccount
    address public immutable WSTETH;

    /// @notice Creates the Lido account implementation.
    constructor(address factory, address oracle, address wstETH, address stETH) Account(factory, oracle, wstETH) {
        STETH = stETH;
        WSTETH = wstETH;
    }

    /// @dev Returns additional stETH value when the vault asset is not stETH.
    function _totalAssets() internal view override returns (uint256 assets) {
        if (_asset == STETH) {
            return 0;
        }

        uint256 stETHBalance = IERC20(STETH).balanceOf(address(this));
        if (stETHBalance > 0) {
            assets = _tokenToRedeemToAssets(IWstETH(WSTETH).getWstETHByStETH(stETHBalance));
        }
    }

    /// @dev Unwraps held wstETH into stETH.
    function _sync() internal override {
        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amountToRedeem == 0) {
            return;
        }
        IWstETH(WSTETH).unwrap(amountToRedeem);
    }
}

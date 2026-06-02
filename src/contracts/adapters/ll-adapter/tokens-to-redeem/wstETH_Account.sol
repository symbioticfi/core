// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "../accounts/Account.sol";

import {IWstETH} from "../../../../interfaces/adapters/ll-adapter/accounts/IWstETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title wstETH_Account
/// @notice Lido account for wstETH redemptions.
contract wstETH_Account is Account {
    address public immutable STETH;
    address public immutable WSTETH;

    constructor(address factory, address oracle, address wstETH, address stETH) Account(factory, oracle, wstETH) {
        WSTETH = wstETH;
        STETH = stETH;
    }

    function _additionalAssets(address asset, uint256 price) internal view override returns (uint256 assets) {
        if (asset == STETH) {
            return 0;
        }

        uint256 stETHBalance = IERC20(STETH).balanceOf(address(this));
        if (stETHBalance > 0) {
            assets = _toAssets(IWstETH(WSTETH).getWstETHByStETH(stETHBalance), price);
        }
    }

    function _requestRedeem(uint256 amountToRedeem, uint256) internal override {
        if (IERC4626(vault).asset() == WSTETH) {
            return;
        }

        IWstETH(WSTETH).unwrap(amountToRedeem);
    }
}

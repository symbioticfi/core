// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "./Account.sol";

import {IThreeJaneAccount} from "../../../interfaces/adapters/ll-adapter/threejane/IThreeJaneAccount.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ThreeJaneAccount
/// @notice Account for 3Jane ERC-4626 redemptions.
contract ThreeJaneAccount is Account, IThreeJaneAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the 3Jane account implementation.
    constructor(address tokenToRedeem, address factory, address oracle) Account(factory, oracle, tokenToRedeem) {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns no additional assets for synchronous 3Jane redemptions.
    function _totalAssets() internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Redeems held 3Jane shares into the vault asset.
    function _sync() internal override {
        uint256 shares = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (shares == 0) {
            return;
        }
        IERC4626(TOKEN_TO_REDEEM).redeem(shares, address(this), address(this));
    }
}

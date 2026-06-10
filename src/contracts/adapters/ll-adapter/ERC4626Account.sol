// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {IERC4626Account} from "../../../interfaces/adapters/ll-adapter/IERC4626Account.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ERC4626Account
/// @notice Account for instant ERC-4626 share redemptions.
contract ERC4626Account is Account, IERC4626Account {
    /* CONSTRUCTOR */

    /// @notice Creates the ERC-4626 account implementation.
    constructor(address factory, address tokenToRedeem, address cowSwapSettlement)
        Account(address(0), factory, tokenToRedeem, cowSwapSettlement)
    {}

    /* INTERNAL FUNCTIONS */

    /// @dev Values held ERC-4626 shares through the vault conversion.
    function _tokenToRedeemToAssets(uint256 amount) internal view override returns (uint256) {
        return IERC4626(TOKEN_TO_REDEEM).convertToAssets(amount);
    }

    /// @dev Returns no additional assets.
    function _totalAssets() internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Redeems held ERC-4626 shares into the vault asset.
    function _sync() internal override {
        uint256 shares = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (shares > 0) {
            IERC4626(TOKEN_TO_REDEEM).redeem(shares, address(this), address(this));
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (IERC4626(TOKEN_TO_REDEEM).asset() != _asset) {
            revert InvalidAsset();
        }
    }
}

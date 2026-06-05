// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "./common/Account.sol";

import {ITheoAccount} from "../../../interfaces/adapters/ll-adapter/theo/ITheoAccount.sol";
import {ISthUSD} from "../../../interfaces/adapters/ll-adapter/theo/ISthUSD.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title TheoAccount
/// @notice Account for Theo sthUSD async redemptions.
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

    /// @dev Returns pending sthUSD redemption request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        address token = TOKEN_TO_REDEEM;
        (assets,,) = ISthUSD(token).currentRedeemRequest(address(this));
        assets = _redemptionTokenToAssets(ISthUSD(token).asset(), assets);
    }

    /// @dev Initiates held sthUSD redemption and claims matured thUSD requests.
    function _sync() internal override {
        address token = TOKEN_TO_REDEEM;
        (, uint256 shares, uint256 claimableTimestamp) = ISthUSD(token).currentRedeemRequest(address(this));
        if (shares > 0) {
            if (block.timestamp < claimableTimestamp) {
                return;
            }

            ISthUSD(token).redeem(shares, address(this), address(this));
        }

        shares = IERC20(token).balanceOf(address(this));
        if (shares > 0) {
            ISthUSD(token).initiateRedeem(shares, address(this));
        }
    }
}

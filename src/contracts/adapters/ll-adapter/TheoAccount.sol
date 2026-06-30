// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {ISthUSD} from "../../../interfaces/adapters/ll-adapter/theo/ISthUSD.sol";
import {ITheoAccount} from "../../../interfaces/adapters/ll-adapter/theo/ITheoAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title TheoAccount
/// @notice Account for Theo sthUSD async redemptions.
contract TheoAccount is Account, ITheoAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Theo account implementation.
    constructor(address oracle, address factory, address tokenToRedeem, address cowSwapSettlement)
        Account(oracle, factory, tokenToRedeem, cowSwapSettlement)
    {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending sthUSD redemption request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        (assets,,) = ISthUSD(TOKEN_TO_REDEEM).currentRedeemRequest(address(this));
        assets = _redemptionTokenToAssets(ISthUSD(TOKEN_TO_REDEEM).asset(), assets);
    }

    /// @dev Initiates held sthUSD redemption and claims matured thUSD requests.
    function _sync() internal override {
        (, uint256 shares, uint256 claimableTimestamp) = ISthUSD(TOKEN_TO_REDEEM).currentRedeemRequest(address(this));
        if (shares > 0) {
            if (block.timestamp < claimableTimestamp) {
                return;
            }

            ISthUSD(TOKEN_TO_REDEEM).redeem(shares, address(this), address(this));
        }

        shares = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (shares > 0) {
            ISthUSD(TOKEN_TO_REDEEM).initiateRedeem(shares, address(this));
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (ISthUSD(TOKEN_TO_REDEEM).asset() != _asset) {
            revert InvalidAsset();
        }
    }
}

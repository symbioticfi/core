// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {IThreeJaneAccount} from "../../../interfaces/adapters/ll-adapter/threejane/IThreeJaneAccount.sol";
import {IThreeJaneSUSD3} from "../../../interfaces/adapters/ll-adapter/threejane/IThreeJaneSUSD3.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ThreeJaneAccount
/// @notice Account for 3Jane sUSD3 cooldown redemptions.
contract ThreeJaneAccount is Account, IThreeJaneAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the 3Jane account implementation.
    constructor(address oracle, address factory, address tokenToRedeem, address cowSwapSettlement)
        Account(oracle, factory, tokenToRedeem, cowSwapSettlement)
    {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns no additional assets because cooldown shares remain held by this account.
    function _totalAssets() internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Starts cooldowns and withdraws matured sUSD3 into USD3 during the withdrawal window.
    function _sync() internal override {
        (uint48 cooldownEnd, uint48 windowEnd, uint256 shares) =
            IThreeJaneSUSD3(TOKEN_TO_REDEEM).getCooldownStatus(address(this));

        if (shares > 0) {
            if (block.timestamp < cooldownEnd) {
                return;
            }

            if (block.timestamp <= windowEnd) {
                uint256 assets = IThreeJaneSUSD3(TOKEN_TO_REDEEM).convertToAssets(shares);
                uint256 availableAssets = IThreeJaneSUSD3(TOKEN_TO_REDEEM).availableWithdrawLimit(address(this));
                if (availableAssets < assets) {
                    assets = availableAssets;
                }
                if (assets > 0) {
                    IThreeJaneSUSD3(TOKEN_TO_REDEEM).withdraw(assets, address(this), address(this));
                }
                return;
            }
        }

        if (block.timestamp < IThreeJaneSUSD3(TOKEN_TO_REDEEM).lockedUntil(address(this))) {
            return;
        }

        shares = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (shares > 0) {
            IThreeJaneSUSD3(TOKEN_TO_REDEEM).startCooldown(shares);
        }
    }
}

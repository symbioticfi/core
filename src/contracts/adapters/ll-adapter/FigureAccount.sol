// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {IFigureAccount} from "../../../interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";
import {IFigureYieldVault} from "../../../interfaces/adapters/ll-adapter/figure/IFigureYieldVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title FigureAccount
/// @notice Account for Figure/Hastra PRIME redemptions through wYLDS.
contract FigureAccount is CooldownAccount, IFigureAccount {
    /* IMMUTABLES */

    /// @dev wYLDS async redeem vault.
    address internal immutable ASYNC_REDEEM_VAULT;

    /* CONSTRUCTOR */

    /// @notice Creates the Figure account implementation.
    constructor(address oracle, address factory, uint48 cooldown, address tokenToRedeem, address cowSwapSettlement)
        CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement)
    {
        ASYNC_REDEEM_VAULT = IERC4626(TOKEN_TO_REDEEM).asset();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IFigureAccount
    function pendingAssets() public view returns (uint256 assets) {
        (, assets,) = IFigureYieldVault(ASYNC_REDEEM_VAULT).pendingRedemptions(address(this));
        assets = _redemptionTokenToAssets(IFigureYieldVault(ASYNC_REDEEM_VAULT).asset(), assets);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Values held PRIME by converting it to wYLDS before valuing wYLDS.
    function _tokenToRedeemToAssets(uint256 amount) internal view override returns (uint256) {
        return IFigureYieldVault(ASYNC_REDEEM_VAULT).convertToAssets(IERC4626(TOKEN_TO_REDEEM).convertToAssets(amount));
    }

    /// @dev Returns held wYLDS value plus pending async redemption request value in vault assets.
    function _totalAssets() internal view override returns (uint256) {
        return pendingAssets()
            + IFigureYieldVault(ASYNC_REDEEM_VAULT).convertToAssets(IERC20(ASYNC_REDEEM_VAULT).balanceOf(address(this)));
    }

    /// @dev Figure redemptions are finalized offchain by the yield vault admin.
    function _finalizeRequests() internal override {}

    /// @dev Submits held PRIME or wYLDS to the Figure yield vault redemption flow.
    function _requestRedeem() internal override {
        (uint256 pendingShares,,) = IFigureYieldVault(ASYNC_REDEEM_VAULT).pendingRedemptions(address(this));
        if (pendingShares > 0) {
            return;
        }

        uint256 primeBalance = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (primeBalance > 0) {
            IERC4626(TOKEN_TO_REDEEM).redeem(primeBalance, address(this), address(this));
        }

        uint256 balance = IERC20(ASYNC_REDEEM_VAULT).balanceOf(address(this));
        if (balance > 0) {
            IFigureYieldVault(ASYNC_REDEEM_VAULT).requestRedeem(balance);
        }
    }
}

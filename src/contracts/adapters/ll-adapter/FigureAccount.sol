// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AsyncRedeemAccount} from "./common/AsyncRedeemAccount.sol";

import {IAsyncRedeemVault} from "../../../interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";
import {IFigureAccount} from "../../../interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title FigureAccount
/// @notice Account for Figure/Hastra PRIME redemptions through wYLDS.
contract FigureAccount is AsyncRedeemAccount, IFigureAccount {
    /* IMMUTABLES */

    /// @dev wYLDS async redeem vault.
    address internal immutable ASYNC_REDEEM_VAULT;

    /* CONSTRUCTOR */

    /// @notice Creates the Figure account implementation.
    constructor(address oracle, address factory, uint48 cooldown, address tokenToRedeem, address cowSwapSettlement)
        AsyncRedeemAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement)
    {
        ASYNC_REDEEM_VAULT = IERC4626(TOKEN_TO_REDEEM).asset();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Values held PRIME by converting it to wYLDS before valuing wYLDS.
    function _tokenToRedeemToAssets(uint256 amount) internal view override returns (uint256) {
        return IAsyncRedeemVault(ASYNC_REDEEM_VAULT).convertToAssets(IERC4626(TOKEN_TO_REDEEM).convertToAssets(amount));
    }

    /// @dev Returns held wYLDS value plus pending async redemption request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        address asyncRedeemVault = _asyncRedeemVault();
        return super._totalAssets()
            + IAsyncRedeemVault(asyncRedeemVault).convertToAssets(IERC20(asyncRedeemVault).balanceOf(address(this)));
    }

    /// @dev Redeems PRIME into wYLDS and submits held wYLDS for async redemption.
    function _requestRedeem() internal override {
        IERC4626(TOKEN_TO_REDEEM).redeem(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), address(this), address(this));
        super._requestRedeem();
    }

    /// @dev Returns wYLDS as the ERC-7540 async redeem vault.
    function _asyncRedeemVault() internal view override returns (address) {
        return ASYNC_REDEEM_VAULT;
    }
}

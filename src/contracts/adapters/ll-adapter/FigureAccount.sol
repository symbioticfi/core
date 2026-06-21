// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {IFigureAccount} from "../../../interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";
import {IFigureSubAccount} from "../../../interfaces/adapters/ll-adapter/figure/IFigureSubAccount.sol";
import {IFigureYieldVault} from "../../../interfaces/adapters/ll-adapter/figure/IFigureYieldVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FigureAccount
/// @notice Account for Figure/Hastra PRIME redemptions through wYLDS.
contract FigureAccount is CooldownAccount, IFigureAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev wYLDS async redeem vault.
    address internal immutable ASYNC_REDEEM_VAULT;
    /// @dev Asset received after wYLDS redemption.
    address internal immutable REDEMPTION_TOKEN;

    /* STATE VARIABLES */

    /// @inheritdoc IFigureAccount
    address[] public subAccounts;

    /* CONSTRUCTOR */

    /// @notice Creates the Figure account implementation.
    constructor(address oracle, address factory, uint48 cooldown, address tokenToRedeem, address cowSwapSettlement)
        CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement)
    {
        ASYNC_REDEEM_VAULT = IERC4626(TOKEN_TO_REDEEM).asset();
        REDEMPTION_TOKEN = IFigureYieldVault(ASYNC_REDEEM_VAULT).asset();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Values held PRIME by converting it to wYLDS before valuing wYLDS.
    function _tokenToRedeemToAssets(uint256 amount) internal view override returns (uint256) {
        amount = IERC4626(TOKEN_TO_REDEEM).convertToAssets(amount);
        return _asset == ASYNC_REDEEM_VAULT
            ? amount
            : _redemptionTokenToAssets(REDEMPTION_TOKEN, IFigureYieldVault(ASYNC_REDEEM_VAULT).convertToAssets(amount));
    }

    /// @dev Returns held wYLDS value plus pending async redemption request value in vault assets.
    function _totalAssets() internal view override returns (uint256) {
        if (_asset == ASYNC_REDEEM_VAULT) {
            return 0;
        }

        uint256 assets;
        for (uint256 i; i < subAccounts.length; ++i) {
            (, uint256 pendingAssets,) = IFigureYieldVault(ASYNC_REDEEM_VAULT).pendingRedemptions(subAccounts[i]);
            assets += _redemptionTokenToAssets(
                REDEMPTION_TOKEN, pendingAssets + IERC20(REDEMPTION_TOKEN).balanceOf(subAccounts[i])
            );
        }

        uint256 balance = IERC20(ASYNC_REDEEM_VAULT).balanceOf(address(this));
        if (balance > 0) {
            assets += _redemptionTokenToAssets(
                REDEMPTION_TOKEN, IFigureYieldVault(ASYNC_REDEEM_VAULT).convertToAssets(balance)
            );
        }

        return assets;
    }

    /// @dev Figure redemptions are finalized offchain by the yield vault admin.
    function _finalizeRequests() internal override {
        for (uint256 i = subAccounts.length; i > 0; --i) {
            uint256 index = i - 1;
            address subAccount = subAccounts[index];

            
            (, uint256 pendingAssets,) = IFigureYieldVault(ASYNC_REDEEM_VAULT).pendingRedemptions(subAccount);
            if (pendingAssets == 0) {
                IFigureSubAccount(subAccount).finalizeRedeem();
                subAccounts[index] = subAccounts[subAccounts.length - 1];
                subAccounts.pop();
            }
        }
    }

    /// @dev Submits held PRIME or wYLDS to the Figure yield vault redemption flow.
    function _requestRedeem() internal override {
        uint256 primeBalance = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (primeBalance > 0) {
            IERC4626(TOKEN_TO_REDEEM).redeem(primeBalance, address(this), address(this));
        }
        if (_asset == ASYNC_REDEEM_VAULT) {
            return;
        }

        uint256 balance = IERC20(ASYNC_REDEEM_VAULT).balanceOf(address(this));
        if (balance > 0) {
            address subAccount = address(new FigureSubAccount(ASYNC_REDEEM_VAULT, address(this), REDEMPTION_TOKEN));

            subAccounts.push(subAccount);
            IERC20(ASYNC_REDEEM_VAULT).safeTransfer(subAccount, balance);
            IFigureSubAccount(subAccount).requestRedeem();
        }
    }
}

/// @title FigureSubAccount
/// @notice Request-holder subaccount for one Figure wYLDS redemption request.
contract FigureSubAccount is IFigureSubAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Figure wYLDS async redeem vault.
    address internal immutable ASYNC_REDEEM_VAULT;
    /// @dev Parent account that owns this subaccount.
    address internal immutable ACCOUNT;
    /// @dev Redemption asset received after queue processing.
    address internal immutable ASSET;

    /* CONSTRUCTOR */

    /// @notice Creates the Figure request-holder subaccount.
    constructor(address asyncRedeemVault, address account, address redemptionToken) {
        ASYNC_REDEEM_VAULT = asyncRedeemVault;
        ACCOUNT = account;
        ASSET = redemptionToken;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IFigureSubAccount
    function requestRedeem() external {
        if (ACCOUNT != msg.sender) {
            revert NotAccount();
        }

        IFigureYieldVault(ASYNC_REDEEM_VAULT).requestRedeem(IERC20(ASYNC_REDEEM_VAULT).balanceOf(address(this)));
    }

    /// @inheritdoc IFigureSubAccount
    function finalizeRedeem() external {
        if (ACCOUNT != msg.sender) {
            revert NotAccount();
        }

        uint256 assets = IERC20(ASSET).balanceOf(address(this));
        if (assets > 0) {
            IERC20(ASSET).safeTransfer(ACCOUNT, assets);
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {IFigureAccount} from "../../../interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";
import {IFigureYieldVault} from "../../../interfaces/adapters/ll-adapter/figure/IFigureYieldVault.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title FigureAccount
/// @notice Account for Figure/Hastra token-to-redeem redemptions through wYLDS.
contract FigureAccount is CooldownAccount, IFigureAccount {
    using Clones for address;
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev wYLDS async redeem vault.
    address internal immutable ASYNC_REDEEM_VAULT;
    /// @dev Asset received after wYLDS redemption.
    address internal immutable REDEMPTION_TOKEN;
    /// @dev Shared logic for Figure request-holder subaccounts.
    address internal immutable SUB_ACCOUNT_IMPLEMENTATION;

    /* STATE VARIABLES */

    /// @inheritdoc IFigureAccount
    address[] public subAccounts;

    /* CONSTRUCTOR */

    /// @notice Creates the Figure account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address subAccountImplementation,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        ASYNC_REDEEM_VAULT = IERC4626(tokenToRedeem).asset();
        REDEMPTION_TOKEN = IFigureYieldVault(ASYNC_REDEEM_VAULT).asset();
        SUB_ACCOUNT_IMPLEMENTATION = subAccountImplementation;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns held wYLDS value plus pending async redemption request value in vault assets.
    function _totalAssets() internal view override returns (uint256) {
        uint256 amount;

        uint256 balance = IERC20(ASYNC_REDEEM_VAULT).balanceOf(address(this));
        if (balance > 0) {
            amount += IFigureYieldVault(ASYNC_REDEEM_VAULT).convertToAssets(balance);
        }

        uint256 length = subAccounts.length;
        for (uint256 i; i < length; ++i) {
            (, uint256 pendingAssets,) = IFigureYieldVault(ASYNC_REDEEM_VAULT).pendingRedemptions(subAccounts[i]);
            amount += pendingAssets + IERC20(REDEMPTION_TOKEN).balanceOf(subAccounts[i]);
        }

        return REDEMPTION_TOKEN == _asset
            ? amount
            : _redemptionTokenToAssets(REDEMPTION_TOKEN, amount + IERC20(REDEMPTION_TOKEN).balanceOf(address(this)));
    }

    /// @dev Figure redemptions are finalized offchain by the yield vault admin.
    function _finalizeRequests() internal override {
        uint256 length = subAccounts.length;
        for (uint256 i = length; i > 0;) {
            address subAccount = subAccounts[--i];
            (uint256 pendingShares,,) = IFigureYieldVault(ASYNC_REDEEM_VAULT).pendingRedemptions(subAccount);
            if (pendingShares == 0) {
                uint256 balance = IERC20(REDEMPTION_TOKEN).balanceOf(subAccount);
                if (balance > 0) {
                    IERC20(REDEMPTION_TOKEN).safeTransferFrom(subAccount, address(this), balance);
                }
                subAccounts[i] = subAccounts[--length];
                subAccounts.pop();
            }
        }
    }

    /// @dev Submits held token-to-redeem or wYLDS to the Figure yield vault redemption flow.
    function _requestRedeem() internal override returns (bool) {
        uint256 tokenToRedeemBalance = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (tokenToRedeemBalance > 0) {
            IERC4626(TOKEN_TO_REDEEM).redeem(tokenToRedeemBalance, address(this), address(this));
        }

        uint256 balance = IERC20(ASYNC_REDEEM_VAULT).balanceOf(address(this));
        if (balance > 0) {
            address subAccount = SUB_ACCOUNT_IMPLEMENTATION.clone();
            IERC20(ASYNC_REDEEM_VAULT).safeTransfer(subAccount, balance);
            FigureSubAccount(subAccount).initialize();

            subAccounts.push(subAccount);
            return true;
        }
        return false;
    }
}

/// @title FigureSubAccount
/// @notice Request-holder subaccount for one Figure wYLDS redemption request.
contract FigureSubAccount is Initializable {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Figure wYLDS async redeem vault.
    address internal immutable ASYNC_REDEEM_VAULT;
    /// @dev Redemption asset received after queue processing.
    address internal immutable REDEMPTION_TOKEN;

    /* CONSTRUCTOR */

    /// @notice Creates the Figure request-holder subaccount.
    constructor(address tokenToRedeem) {
        ASYNC_REDEEM_VAULT = IERC4626(tokenToRedeem).asset();
        REDEMPTION_TOKEN = IFigureYieldVault(ASYNC_REDEEM_VAULT).asset();
    }

    /* PUBLIC FUNCTIONS */

    function initialize() external initializer {
        IERC20(REDEMPTION_TOKEN).forceApprove(msg.sender, type(uint256).max);
        IFigureYieldVault(ASYNC_REDEEM_VAULT).requestRedeem(IERC20(ASYNC_REDEEM_VAULT).balanceOf(address(this)));
    }
}

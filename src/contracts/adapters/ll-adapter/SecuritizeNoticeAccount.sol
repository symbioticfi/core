// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {
    ISecuritizeNoticeAccount
} from "../../../interfaces/adapters/ll-adapter/securitize/ISecuritizeNoticeAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SecuritizeNoticeAccount
/// @notice Account for one in-flight Securitize redemption notice settled offchain.
contract SecuritizeNoticeAccount is Account, ISecuritizeNoticeAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc ISecuritizeNoticeAccount
    address public immutable REDEMPTION_WALLET;
    /// @inheritdoc ISecuritizeNoticeAccount
    uint48 public immutable SETTLEMENT_DURATION;

    /* STATE VARIABLES */

    /// @inheritdoc ISecuritizeNoticeAccount
    uint256 public pendingAssets;
    /// @inheritdoc ISecuritizeNoticeAccount
    uint48 public pendingExpiry;

    /* CONSTRUCTOR */

    /// @notice Creates a Securitize notice account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address redemptionWallet,
        uint48 settlementDuration,
        address cowSwapSettlement
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement) {
        REDEMPTION_WALLET = redemptionWallet;
        SETTLEMENT_DURATION = settlementDuration;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the unexpired receivable not already covered by newly arrived settlement assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 pending = pendingAssets;
        if (pending == 0 || block.timestamp >= pendingExpiry) {
            return 0;
        }

        uint256 unreconciled = _unreconciledAssets();
        return pending > unreconciled ? pending - unreconciled : 0;
    }

    /// @dev Reconciles settlement, writes off expiry, unlocks realized assets, then submits queued tokens.
    function _sync() internal override {
        uint256 pending = pendingAssets;
        if (pending > 0) {
            uint256 unreconciled = _unreconciledAssets();
            if (unreconciled > 0) {
                uint256 reconciled = unreconciled < pending ? unreconciled : pending;
                pending -= reconciled;
                pendingAssets = pending;
                emit ReconcileSettlement(reconciled, pending);
                if (pending == 0) {
                    pendingExpiry = 0;
                }
            }

            if (pending > 0 && block.timestamp >= pendingExpiry) {
                emit WriteOff(pending);
                pendingAssets = 0;
                pendingExpiry = 0;
                pending = 0;
            }
        }

        IERC20(_asset).forceApprove(adapter, IERC20(_asset).balanceOf(address(this)));

        if (pending == 0) {
            uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
            if (amount > 0) {
                uint256 assets = _tokenToRedeemToAssets(amount);
                uint48 expiry = uint48(block.timestamp) + SETTLEMENT_DURATION;
                pendingAssets = assets;
                pendingExpiry = expiry;
                IERC20(TOKEN_TO_REDEEM).safeTransfer(REDEMPTION_WALLET, amount);
                emit RequestRedeem(amount, assets, expiry);
            }
        }
    }

    /// @dev Returns assets received since the last sync; exact allowances fall with adapter pulls.
    function _unreconciledAssets() internal view returns (uint256 assets) {
        uint256 balance = IERC20(_asset).balanceOf(address(this));
        uint256 allowance = IERC20(_asset).allowance(address(this), adapter);
        if (balance > allowance) {
            assets = balance - allowance;
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the account and replaces the base maximum approval with the exact held balance.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        IERC20(_asset).forceApprove(adapter, IERC20(_asset).balanceOf(address(this)));
    }
}

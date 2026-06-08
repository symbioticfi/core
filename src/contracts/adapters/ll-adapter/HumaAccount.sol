// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {IHumaAccount} from "../../../interfaces/adapters/ll-adapter/huma/IHumaAccount.sol";
import {IHumaTrancheVault} from "../../../interfaces/adapters/ll-adapter/huma/IHumaTrancheVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title HumaAccount
/// @notice Account for Huma Institutional tranche redemptions.
contract HumaAccount is Account, IHumaAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IHumaAccount
    address public immutable REDEMPTION_VAULT;

    /* STATE VARIABLES */

    /// @inheritdoc IHumaAccount
    uint256 public pendingAssets;

    /* CONSTRUCTOR */

    /// @notice Creates the Huma account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address redemptionVault,
        address cowSwapSettlement
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement) {
        REDEMPTION_VAULT = redemptionVault;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns requested value no longer held as tranche tokens.
    function _totalAssets() internal view override returns (uint256 assets) {
        assets = pendingAssets;
    }

    /// @dev Claims fulfilled proceeds and submits held tranche tokens for redemption.
    function _sync() internal override {
        uint256 assetsBefore = IERC20(_asset).balanceOf(address(this));

        try IHumaTrancheVault(REDEMPTION_VAULT).disburse() {} catch {}

        try IHumaTrancheVault(REDEMPTION_VAULT).withdrawAfterPoolClosure() {} catch {}

        uint256 claimedAssets = IERC20(_asset).balanceOf(address(this)) - assetsBefore;
        if (claimedAssets > 0) {
            pendingAssets = claimedAssets >= pendingAssets ? 0 : pendingAssets - claimedAssets;
        }

        uint256 shares = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (shares > 0) {
            IHumaTrancheVault(REDEMPTION_VAULT).addRedemptionRequest(shares);

            uint256 requestedShares = shares - IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
            if (requestedShares > 0) {
                pendingAssets += _tokenToRedeemToAssets(requestedShares);
            }
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal override {
        super._initialize(initialVersion, owner_, data);
        IERC20(TOKEN_TO_REDEEM).forceApprove(REDEMPTION_VAULT, type(uint256).max);
    }
}

// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "./Account.sol";

import {IPikuFundingManager} from "../../../interfaces/adapters/ll-adapter/piku/IPikuFundingManager.sol";
import {IPikuFundingManagerAccount} from "../../../interfaces/adapters/ll-adapter/piku/IPikuFundingManagerAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PikuFundingManagerAccount
/// @notice Account for Piku funding manager queued redemptions.
contract PikuFundingManagerAccount is Account, IPikuFundingManagerAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IPikuFundingManagerAccount
    address public immutable FUNDING_MANAGER;

    /* STATE VARIABLES */

    /// @inheritdoc IPikuFundingManagerAccount
    uint256 public pendingAssets;

    /* CONSTRUCTOR */

    /// @notice Creates the Piku funding manager account implementation.
    constructor(address fundingManager, address tokenToRedeem, address factory, address oracle)
        Account(factory, oracle, tokenToRedeem)
    {
        FUNDING_MANAGER = fundingManager;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns requested value no longer held as Piku tokens.
    function _totalAssets() internal view override returns (uint256 assets) {
        assets = pendingAssets;
    }

    /// @dev Claims fulfilled proceeds and submits held Piku tokens for redemption.
    function _sync() internal override {
        uint256 assetsBefore = IERC20(_asset).balanceOf(address(this));
        IPikuFundingManager fundingManager = IPikuFundingManager(FUNDING_MANAGER);

        try fundingManager.claim() {} catch {}

        uint256 claimedAssets = IERC20(_asset).balanceOf(address(this)) - assetsBefore;
        if (claimedAssets > 0) {
            pendingAssets = claimedAssets >= pendingAssets ? 0 : pendingAssets - claimedAssets;
        }

        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        fundingManager.sell(amount, 0);

        uint256 requested = amount - IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (requested > 0) {
            pendingAssets += _tokenToRedeemToAssets(requested);
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal override {
        super._initialize(initialVersion, owner_, data);
        IERC20(TOKEN_TO_REDEEM).forceApprove(FUNDING_MANAGER, type(uint256).max);
    }
}

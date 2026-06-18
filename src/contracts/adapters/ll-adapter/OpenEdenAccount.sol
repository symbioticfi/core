// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {IOpenEdenAccount} from "../../../interfaces/adapters/ll-adapter/openeden/IOpenEdenAccount.sol";
import {IOpenEdenExpress} from "../../../interfaces/adapters/ll-adapter/openeden/IOpenEdenExpress.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title OpenEdenAccount
/// @notice Account for OpenEden HYBONDExpress queued redemptions.
contract OpenEdenAccount is CooldownAccount, IOpenEdenAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IOpenEdenAccount
    address public immutable EXPRESS;

    /* CONSTRUCTOR */

    /// @notice Creates the OpenEden account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address express,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        EXPRESS = express;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending and final queued HYBOND redemption value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 tokenAmount = IOpenEdenExpress(EXPRESS).pendingRedeemInfo(address(this))
            + IOpenEdenExpress(EXPRESS).redeemInfo(address(this));

        if (tokenAmount > 0) {
            (,, assets) = IOpenEdenExpress(EXPRESS).previewRedeem(tokenAmount);
        }
    }

    /// @dev HYBONDExpress sends USDC directly to this account when the queue is processed.
    function _finalizeRequests() internal override {}

    /// @dev Submits held HYBOND into the HYBONDExpress redemption queue.
    function _requestRedeem() internal override {
        IOpenEdenExpress(EXPRESS).requestRedeem(address(this), IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)));
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (IOpenEdenExpress(EXPRESS).redeemAsset() != _asset) {
            revert InvalidAsset();
        }
        IERC20(TOKEN_TO_REDEEM).forceApprove(EXPRESS, type(uint256).max);
    }
}

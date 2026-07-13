// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {
    IOpenEdenAccount,
    MAX_REDEEM_QUEUE_LENGTH
} from "../../../interfaces/adapters/ll-adapter/openeden/IOpenEdenAccount.sol";
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
    /// @dev Asset received after HYBOND redemption.
    address internal immutable REDEMPTION_TOKEN;

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
        REDEMPTION_TOKEN = IOpenEdenExpress(express).redeemAsset();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending, final queued, and settled HYBOND redemption value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 amount = IOpenEdenExpress(EXPRESS).pendingRedeemInfo(address(this));

        uint256 redeemAmount = IOpenEdenExpress(EXPRESS).redeemInfo(address(this));
        if (redeemAmount > 0) {
            uint256 length = IOpenEdenExpress(EXPRESS).getRedeemQueueLength();
            if (length < MAX_REDEEM_QUEUE_LENGTH) {
                uint256 redemptionTokenAmount;
                for (uint256 i; i < length; ++i) {
                    (, address receiver,,, uint256 redeemAssetAmt, uint256 feeAssetAmt,,) =
                        IOpenEdenExpress(EXPRESS).getRedeemQueueInfo(i);
                    if (receiver == address(this)) {
                        redemptionTokenAmount += redeemAssetAmt - feeAssetAmt;
                    }
                }
                assets += _redemptionTokenToAssets(REDEMPTION_TOKEN, redemptionTokenAmount);
            } else {
                amount += redeemAmount;
            }
        }
        assets += _tokenToRedeemToAssets(amount);

        if (REDEMPTION_TOKEN != _asset) {
            assets += _redemptionTokenToAssets(REDEMPTION_TOKEN, IERC20(REDEMPTION_TOKEN).balanceOf(address(this)));
        }
    }

    /// @dev HYBONDExpress sends USDC directly to this account when the queue is processed.
    function _finalizeRequests() internal override {}

    /// @dev Submits held HYBOND into the HYBONDExpress redemption queue.
    function _requestRedeem() internal override returns (bool) {
        IOpenEdenExpress(EXPRESS).requestRedeem(address(this), IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)));
        return true;
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        IERC20(TOKEN_TO_REDEEM).forceApprove(EXPRESS, type(uint256).max);
    }
}

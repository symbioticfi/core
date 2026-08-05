// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {
    ISecuritizeLiquidityProvider,
    ISecuritizeOffRamp
} from "../../../interfaces/adapters/ll-adapter/securitize/ISecuritizeOffRamp.sol";
import {
    ISecuritizeOffRampAccount
} from "../../../interfaces/adapters/ll-adapter/securitize/ISecuritizeOffRampAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SecuritizeOffRampAccount
/// @notice Account for atomic Securitize redemptions through a native off-ramp.
contract SecuritizeOffRampAccount is Account, ISecuritizeOffRampAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc ISecuritizeOffRampAccount
    address public immutable OFF_RAMP;
    /// @inheritdoc ISecuritizeOffRampAccount
    address public immutable REDEMPTION_TOKEN;

    /* CONSTRUCTOR */

    /// @notice Creates a Securitize off-ramp account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address offRamp,
        address redemptionToken,
        address cowSwapSettlement
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement) {
        OFF_RAMP = offRamp;
        REDEMPTION_TOKEN = redemptionToken;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Atomic redemptions have no pending value beyond held balances.
    function _totalAssets() internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Redeems the full held balance using the off-ramp's quote as same-call slippage protection.
    function _sync() internal override {
        _validateRoute();

        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        uint256 quote = ISecuritizeOffRamp(OFF_RAMP).calculateLiquidityTokenAmount(amount);
        uint256 expected = _tokenToRedeemToAssets(amount);
        if (quote < expected) {
            revert InsufficientQuote(quote, expected);
        }

        uint256 balanceBefore = IERC20(REDEMPTION_TOKEN).balanceOf(address(this));
        IERC20(TOKEN_TO_REDEEM).forceApprove(OFF_RAMP, amount);
        ISecuritizeOffRamp(OFF_RAMP).redeem(amount, quote);
        IERC20(TOKEN_TO_REDEEM).forceApprove(OFF_RAMP, 0);

        uint256 balanceAfter = IERC20(REDEMPTION_TOKEN).balanceOf(address(this));
        uint256 received = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
        if (received < quote) {
            revert InsufficientOutput(received, quote);
        }
    }

    /// @dev Revalidates the upgradeable off-ramp's input and output routes.
    function _validateRoute() internal view {
        if (ISecuritizeOffRamp(OFF_RAMP).assetAddress() != TOKEN_TO_REDEEM) {
            revert InvalidTokenToRedeem();
        }

        address liquidityProvider = ISecuritizeOffRamp(OFF_RAMP).liquidityProvider();
        if (
            _asset != REDEMPTION_TOKEN || liquidityProvider == address(0)
                || ISecuritizeLiquidityProvider(liquidityProvider).liquidityToken() != REDEMPTION_TOKEN
        ) {
            revert InvalidAsset();
        }
    }
}

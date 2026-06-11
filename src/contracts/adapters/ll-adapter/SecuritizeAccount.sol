// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {SettlementAccount, SettlementSubAccount} from "./common/SettlementAccount.sol";

import {ISecuritizeAccount} from "../../../interfaces/adapters/ll-adapter/securitize/ISecuritizeAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SecuritizeAccount
/// @notice Account for Securitize off-chain settlement redemptions with windowed repurchases.
/// @dev The redemption notice is an ERC-20 transfer to the issuer's redemption wallet; settlement
///      returns vault assets for the repurchased portion and re-mints any unfilled remainder to the
///      subaccount, which sweeps it back for re-tender in the next window.
contract SecuritizeAccount is SettlementAccount, ISecuritizeAccount {
    /* IMMUTABLES */

    /// @inheritdoc ISecuritizeAccount
    address public immutable REDEMPTION_WALLET;

    /* CONSTRUCTOR */

    /// @notice Creates the Securitize account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionWallet,
        uint48 initialCutoff,
        uint48 initialCutoffPeriod,
        uint48 valuationDelay,
        uint48 settlementDuration,
        address cowSwapSettlement
    )
        SettlementAccount(
            oracle,
            factory,
            cooldown,
            tokenToRedeem,
            initialCutoff,
            initialCutoffPeriod,
            valuationDelay,
            settlementDuration,
            cowSwapSettlement
        )
    {
        REDEMPTION_WALLET = redemptionWallet;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Deploys a Securitize request-holder subaccount.
    function _createSubAccount() internal override returns (address subAccount) {
        return address(new SecuritizeSubAccount(_asset, address(this), TOKEN_TO_REDEEM, REDEMPTION_WALLET));
    }
}

/// @title SecuritizeSubAccount
/// @notice Request-holder subaccount for one Securitize off-chain redemption.
contract SecuritizeSubAccount is SettlementSubAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Securitize redemption wallet receiving the redemption notice transfer.
    address internal immutable REDEMPTION_WALLET;

    /* CONSTRUCTOR */

    /// @notice Creates the Securitize request-holder subaccount.
    constructor(address asset, address account, address tokenToRedeem, address redemptionWallet)
        SettlementSubAccount(asset, account, tokenToRedeem)
    {
        REDEMPTION_WALLET = redemptionWallet;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Transfers held Securitize tokens to the redemption wallet as the redemption notice.
    function _executeRedemption() internal override {
        IERC20(TOKEN_TO_REDEEM).safeTransfer(REDEMPTION_WALLET, IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)));
    }
}

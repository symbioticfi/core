// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "./Account.sol";

import {IAcredAccount} from "../../../interfaces/adapters/ll-adapter/securitize/IAcredAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SecuritizeAccount
/// @notice Base account for Securitize redemption integrations.
abstract contract SecuritizeAccount is Account {
    /// @notice Creates the Securitize account implementation.
    constructor(address factory, address oracle, address tokenToRedeem) Account(factory, oracle, tokenToRedeem) {}

    /// @dev Returns no additional assets for base Securitize accounts.
    function _totalAssets() internal pure override returns (uint256) {
        return 0;
    }
}

/// @title AcredAccount
/// @notice Account for ACRED redemptions.
abstract contract AcredAccount is SecuritizeAccount, IAcredAccount {
    using SafeERC20 for IERC20;

    /// @inheritdoc IAcredAccount
    address public immutable REDEMPTION_WALLET;

    /// @inheritdoc IAcredAccount
    uint48 public constant POINT_0 = 1_777_593_599;
    /// @inheritdoc IAcredAccount
    uint48 public constant POINT_1 = 1_785_542_399;
    /// @inheritdoc IAcredAccount
    uint48 public constant POINT_2 = 1_793_404_799;
    /// @inheritdoc IAcredAccount
    uint48 public constant POINT_3 = 1_801_267_199;

    /// @notice Creates the ACRED account implementation.
    constructor(address factory, address oracle, address tokenToRedeem, address redemptionWallet)
        SecuritizeAccount(factory, oracle, tokenToRedeem)
    {
        REDEMPTION_WALLET = redemptionWallet;
    }

    /// @dev Transfers held ACRED to the redemption wallet.
    function _sync() internal override {
        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amountToRedeem == 0) {
            return;
        }
        IERC20(TOKEN_TO_REDEEM).safeTransfer(REDEMPTION_WALLET, amountToRedeem);
    }
}

// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "./Account.sol";

import {IDigiFTAccount} from "../../../interfaces/adapters/ll-adapter/digift/IDigiFTAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title DigiFTAccount
/// @notice Account for DigiFT redemption transfers.
contract DigiFTAccount is Account, IDigiFTAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IDigiFTAccount
    address public immutable REDEMPTION_WALLET;

    /* CONSTRUCTOR */

    /// @notice Creates the DigiFT account implementation.
    constructor(address redemptionWallet, address tokenToRedeem, address factory, address oracle)
        Account(factory, oracle, tokenToRedeem)
    {
        REDEMPTION_WALLET = redemptionWallet;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns no additional assets for DigiFT redemption transfers.
    function _totalAssets() internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Transfers held DigiFT tokens to the configured redemption wallet.
    function _sync() internal override {
        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amountToRedeem == 0) {
            return;
        }
        IERC20(TOKEN_TO_REDEEM).safeTransfer(REDEMPTION_WALLET, amountToRedeem);
    }
}

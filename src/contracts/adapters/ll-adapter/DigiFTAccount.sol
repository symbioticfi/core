// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {IDigiFTAccount} from "../../../interfaces/adapters/ll-adapter/digift/IDigiFTAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title DigiFTAccount
/// @notice Account for DigiFT off-chain redemption transfers.
contract DigiFTAccount is Account, IDigiFTAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IDigiFTAccount
    address public immutable REDEMPTION_WALLET;

    /* CONSTRUCTOR */

    /// @notice Creates the DigiFT account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address redemptionWallet,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement, cowSwapVaultRelayer) {
        REDEMPTION_WALLET = redemptionWallet;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns no additional assets after tokens leave the account for off-chain processing.
    function _totalAssets() internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Initiates redemption by sending held DigiFT tokens to the configured wallet.
    ///      DigiFT processing is off-chain; any resulting vault-asset proceeds must be sent back separately.
    function _sync() internal override {
        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amountToRedeem > 0) {
            IERC20(TOKEN_TO_REDEEM).safeTransfer(REDEMPTION_WALLET, amountToRedeem);
        }
    }
}

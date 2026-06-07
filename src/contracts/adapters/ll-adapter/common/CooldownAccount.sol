// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./Account.sol";

import {ICooldownAccount} from "../../../../interfaces/adapters/ll-adapter/ICooldownAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title CooldownAccount
/// @notice Base account with cooldown-gated request submission.
abstract contract CooldownAccount is Account, ICooldownAccount {
    /* IMMUTABLES */

    /// @inheritdoc ICooldownAccount
    uint48 public immutable COOLDOWN;

    /* STATE VARIABLES */

    /// @inheritdoc ICooldownAccount
    uint48 public lastRequestTimestamp;

    /* CONSTRUCTOR */

    /// @notice Creates the cooldown account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement, cowSwapVaultRelayer) {
        COOLDOWN = cooldown;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Finalizes existing requests and submits a new request when cooldown permits.
    function _sync() internal virtual override {
        _finalizeRequests();

        if (
            (msg.sender == owner() || lastRequestTimestamp == 0 || block.timestamp >= lastRequestTimestamp + COOLDOWN)
                && IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)) > 0
        ) {
            _requestRedeem();
            lastRequestTimestamp = uint48(block.timestamp);
        }
    }

    /// @dev Finalizes or clears completed requests.
    function _finalizeRequests() internal virtual;

    /// @dev Submits a redemption request for amount.
    function _requestRedeem() internal virtual;
}

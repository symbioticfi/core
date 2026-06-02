// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mTBILL_Account
/// @notice Token-specific compounding Midas account for mTBILL redemptions.
contract mTBILL_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0xDD629E5241CbC5919847783e6C96B2De4754e438;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0xF6e51d24F4793Ac5e71e0502213a9BBE3A6d4517;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 3 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

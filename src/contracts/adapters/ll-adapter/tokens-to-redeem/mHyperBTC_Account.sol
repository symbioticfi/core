// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mHyperBTC_Account
/// @notice Token-specific compounding Midas account for mHyperBTC redemptions.
contract mHyperBTC_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0xC8495EAFf71D3A563b906295fCF2f685b1783085;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x16d4f955B0aA1b1570Fe3e9bB2f8c19C407cdb67;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 7 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

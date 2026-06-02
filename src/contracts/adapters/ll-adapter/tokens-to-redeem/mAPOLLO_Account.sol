// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mAPOLLO_Account
/// @notice Token-specific compounding Midas account for mAPOLLO redemptions.
contract mAPOLLO_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x7CF9DEC92ca9FD46f8d86e7798B72624Bc116C05;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x5aeA6D35ED7B3B7aE78694B7da2Ee880756Af5C0;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 3 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

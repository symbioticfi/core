// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mROX_Account
/// @notice Token-specific compounding Midas account for mROX redemptions.
contract mROX_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x67E1F506B148d0Fc95a4E3fFb49068ceB6855c05;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0xc33dAdA688f224c514682Ec6Ba940888d43C4b29;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 3 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

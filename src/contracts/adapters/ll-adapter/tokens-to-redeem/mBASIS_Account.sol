// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mBASIS_Account
/// @notice Token-specific compounding Midas account for mBASIS redemptions.
contract mBASIS_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x2a8c22E3b10036f3AEF5875d04f8441d4188b656;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x19AB19e61A930bc5C7B75Bf06cDd954218Ca9F0b;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 7 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

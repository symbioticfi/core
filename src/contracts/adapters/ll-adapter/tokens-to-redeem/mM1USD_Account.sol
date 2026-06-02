// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mM1USD_Account
/// @notice Token-specific compounding Midas account for mM1-USD redemptions.
contract mM1USD_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0xCc5C22C7A6BCC25e66726AeF011dDE74289ED203;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x70Ba3211f2584Bf1C8a2aCdF0a00dba559CE1Ffa;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 17 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

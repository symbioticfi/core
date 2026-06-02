// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mGLOBAL_Account
/// @notice Token-specific compounding Midas account for mGLOBAL redemptions.
contract mGLOBAL_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x1e0fd66753198c7b8bA64edEe8d41D8628Bf20D7;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 65 days;
    uint256 internal constant TOKEN_COOLDOWN = 6 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

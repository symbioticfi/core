// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasNonCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mFONE_Account
/// @notice Token-specific non-compounding Midas account for mF-ONE redemptions.
contract mFONE_Account is MidasNonCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x44b0440e35c596e858cEA433D0d82F5a985fD19C;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 35 days;
    uint256 internal constant TOKEN_COOLDOWN = 3 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasNonCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

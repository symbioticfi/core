// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mRe7YIELD_Account
/// @notice Token-specific compounding Midas account for mRe7YIELD redemptions.
contract mRe7YIELD_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x87C9053C819bB28e0D73d33059E1b3DA80AFb0cf;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x5356B8E06589DE894D86B24F4079c629E8565234;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 24 days;
    uint256 internal constant TOKEN_COOLDOWN = 2 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

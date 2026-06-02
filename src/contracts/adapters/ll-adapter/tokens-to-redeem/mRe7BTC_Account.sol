// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mRe7BTC_Account
/// @notice Token-specific compounding Midas account for mRe7BTC redemptions.
contract mRe7BTC_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x9FB442d6B612a6dcD2acC67bb53771eF1D9F661A;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x4Fd4DD7171D14e5bD93025ec35374d2b9b4321b0;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 24 days;
    uint256 internal constant TOKEN_COOLDOWN = 2 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

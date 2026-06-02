// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mHyperETH_Account
/// @notice Token-specific compounding Midas account for mHyperETH redemptions.
contract mHyperETH_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x5a42864b14C0C8241EF5ab62Dae975b163a2E0C1;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x15f724b35A75F0c28F352b952eA9D1b24e348c57;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 7 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

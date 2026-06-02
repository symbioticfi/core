// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mHYPER_Account
/// @notice Token-specific compounding Midas account for mHYPER redemptions.
contract mHYPER_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x9b5528528656DBC094765E2abB79F293c21191B9;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x6Be2f55816efd0d91f52720f096006d63c366e98;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 3 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

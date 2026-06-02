// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mSL_Account
/// @notice Token-specific compounding Midas account for mSL redemptions.
contract mSL_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x76CC16608aA7Cd32631bb151801bb095313F7bbd;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x8Bee3870Ad8293dcE79E6f4cb049F7531Bd57c22;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 3 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

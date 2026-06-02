// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mMEV_Account
/// @notice Token-specific compounding Midas account for mMEV redemptions.
contract mMEV_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x030b69280892c888670EDCDCD8B69Fd8026A0BF3;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0xac14a14f578C143625Fc8F54218911e8F634184D;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 3 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

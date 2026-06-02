// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title msyrupUSDp_Account
/// @notice Token-specific compounding Midas account for msyrupUSDp redemptions.
contract msyrupUSDp_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x2fE058CcF29f123f9dd2aEC0418AA66a877d8E50;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x71EFa7AF1686C5c04AA34a120a91cb4262679C44;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 3 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

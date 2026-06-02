// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mEVUSD_Account
/// @notice Token-specific compounding Midas account for mEVUSD redemptions.
contract mEVUSD_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x548857309BEfb6Fb6F20a9C5A56c9023D892785B;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x9C3743582e8b2d7cCb5e08caF3c9C33780ac446f;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 3 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

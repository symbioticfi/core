// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompTokenRedeemAccount} from "./MidasTokenRedeemAccount.sol";

/// @title mEDGE_Account
/// @notice Token-specific compounding Midas account for mEDGE redemptions.
contract mEDGE_Account is MidasCompTokenRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0xbB51E2a15A9158EBE2b0Ceb8678511e063AB7a55;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x9B2C5E30E3B1F6369FC746A1C1E47277396aF15D;
    uint256 public constant MAX_WITHDRAWAL_DELAY = 3 days;
    uint256 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompTokenRedeemAccount(
            factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, REDEMPTION_VAULT_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

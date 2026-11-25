// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MidasCompAccount} from "../MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IMidasTokenAccount} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasTokenAccount.sol";

contract msyrupUSDp_Account is MidasCompAccount, IMidasTokenAccount {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    /// @dev Unlike the other Midas USD vaults, this redemption vault lists only USDT as a payment
    ///      token, so USDC would be rejected. MidasAccount._requestRedeem falls back to
    ///      REDEMPTION_TOKEN when the vault has no config for the vault asset, and the USDT is
    ///      settled back to the vault asset through the CoW converter.
    address internal constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant TOKEN_ADDRESS = 0x2fE058CcF29f123f9dd2aEC0418AA66a877d8E50;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x71EFa7AF1686C5c04AA34a120a91cb4262679C44;

    constructor(address factory, address cowSwapSettlement)
        MidasCompAccount(
            address(
                new MidasOracle(
                    264_400_000_000_000_000,
                    3_701_100_000_000_000_000,
                    address(IMidasRedemptionVault(REDEMPTION_VAULT_ADDRESS).mTokenDataFeed())
                )
            ),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            MAINNET_USDT,
            REDEMPTION_VAULT_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract msyrupUSDp_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

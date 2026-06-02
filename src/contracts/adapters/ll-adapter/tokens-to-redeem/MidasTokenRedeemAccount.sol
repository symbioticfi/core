// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompAccount, MidasNonCompAccount} from "../accounts/MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/accounts/IMidasRedemptionVault.sol";

/// @title MidasCompTokenRedeemAccount
/// @notice Base for token-specific compounding Midas accounts.
abstract contract MidasCompTokenRedeemAccount is MidasCompAccount {
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    constructor(
        address factory,
        uint256 cooldown,
        address tokenToRedeem,
        address redemptionVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    )
        MidasCompAccount(
            address(new MidasOracle(address(IMidasRedemptionVault(redemptionVault).mTokenDataFeed()))),
            factory,
            cooldown,
            tokenToRedeem,
            MAINNET_USDC,
            redemptionVault,
            cowSwapSettlement,
            cowSwapVaultRelayer
        )
    {}
}

/// @title MidasNonCompTokenRedeemAccount
/// @notice Base for token-specific non-compounding Midas accounts.
abstract contract MidasNonCompTokenRedeemAccount is MidasNonCompAccount {
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    constructor(
        address factory,
        uint256 cooldown,
        address tokenToRedeem,
        address redemptionVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    )
        MidasNonCompAccount(
            address(new MidasOracle(address(IMidasRedemptionVault(redemptionVault).mTokenDataFeed()))),
            factory,
            cooldown,
            tokenToRedeem,
            MAINNET_USDC,
            redemptionVault,
            cowSwapSettlement,
            cowSwapVaultRelayer
        )
    {}
}

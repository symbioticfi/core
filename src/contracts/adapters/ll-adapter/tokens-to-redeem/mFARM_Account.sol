// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MidasCompAccount} from "../MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IMidasTokenAccount} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasTokenAccount.sol";

contract mFARM_Account is MidasCompAccount, IMidasTokenAccount {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint48 public constant MAX_WITHDRAWAL_DELAY = 7 days;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant TOKEN_ADDRESS = 0xA19f6e0dF08a7917F2F8A33Db66D0AF31fF5ECA6;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0xf4F042D90f0C0d3ABA4A30Caa6Ac124B14A7e600;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        MidasCompAccount(
            address(new MidasOracle(address(IMidasRedemptionVault(REDEMPTION_VAULT_ADDRESS).mTokenDataFeed()))),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            MAINNET_USDC,
            REDEMPTION_VAULT_ADDRESS,
            cowSwapSettlement,
            cowSwapVaultRelayer
        )
    {}
}

contract mFARM_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

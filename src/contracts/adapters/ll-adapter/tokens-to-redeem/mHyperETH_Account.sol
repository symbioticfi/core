// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MidasCompAccount} from "../MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IMidasTokenAccount} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasTokenAccount.sol";

contract mHyperETH_Account is MidasCompAccount, IMidasTokenAccount {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint48 public constant MAX_WITHDRAWAL_DELAY = 7 days;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant TOKEN_ADDRESS = 0x5a42864b14C0C8241EF5ab62Dae975b163a2E0C1;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x15f724b35A75F0c28F352b952eA9D1b24e348c57;

    constructor(address factory, address cowSwapSettlement)
        MidasCompAccount(
            address(new MidasOracle(address(IMidasRedemptionVault(REDEMPTION_VAULT_ADDRESS).mTokenDataFeed()))),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            MAINNET_USDC,
            REDEMPTION_VAULT_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract mHyperETH_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

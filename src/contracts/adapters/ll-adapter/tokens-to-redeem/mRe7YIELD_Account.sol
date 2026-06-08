// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MidasCompAccount} from "../MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IMidasTokenAccount} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasTokenAccount.sol";

contract mRe7YIELD_Account is MidasCompAccount, IMidasTokenAccount {
    uint48 internal constant TOKEN_COOLDOWN = 2 days;
    uint48 public constant MAX_WITHDRAWAL_DELAY = 24 days;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant TOKEN_ADDRESS = 0x87C9053C819bB28e0D73d33059E1b3DA80AFb0cf;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x5356B8E06589DE894D86B24F4079c629E8565234;

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

contract mRe7YIELD_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

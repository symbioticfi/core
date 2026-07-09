// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CutoffMidasAccount} from "../MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IMidasTokenAccount} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasTokenAccount.sol";

contract mGLOBAL_Account is CutoffMidasAccount, IMidasTokenAccount {
    uint48 internal constant TOKEN_COOLDOWN = 12 hours;
    uint48 internal constant TOKEN_PRE_CUTOFF_WINDOW = 5 days;
    uint48 internal constant TOKEN_INITIAL_CUTOFF = 1_785_074_400;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant TOKEN_ADDRESS = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;
    address internal constant ORACLE_DATA_FEED = 0x66Aa9fcD63DF74e1f67A9452E6E59Fbc67f75E38;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x1e0fd66753198c7b8bA64edEe8d41D8628Bf20D7;

    constructor(address factory, address cowSwapSettlement)
        CutoffMidasAccount(
            address(new MidasOracle(251_400_000_000_000_000, 3_520_200_000_000_000_000, ORACLE_DATA_FEED)),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_INITIAL_CUTOFF,
            TOKEN_ADDRESS,
            TOKEN_PRE_CUTOFF_WINDOW,
            MAINNET_USDC,
            REDEMPTION_VAULT_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract mGLOBAL_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

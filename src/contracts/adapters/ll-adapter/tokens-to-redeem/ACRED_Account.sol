// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SecuritizeAccount} from "../SecuritizeAccount.sol";

contract ACRED_Account is SecuritizeAccount {
    address internal constant TOKEN_ADDRESS = 0x17418038ecF73BA4026c4f428547BF099706F27B;
    address internal constant REDEMPTION_WALLET_ADDRESS = 0xbb543C77436645C8b95B64eEc39E3C0d48D4842b;
    uint48 internal constant TOKEN_COOLDOWN = 9 days;
    /// @dev 2026-08-01 00:00:00 UTC — day after the 2026-07-31 feeder repurchase deadline, so deadline-day
    ///      tenders join the closing cohort; 91-day rolls land on deadline+1 for the published 2026-27
    ///      schedule (10/31, 01/30, 05/01); owner-maintained thereafter.
    uint48 internal constant TOKEN_INITIAL_CUTOFF = 1_785_542_400;
    uint48 internal constant TOKEN_INITIAL_CUTOFF_PERIOD = 91 days;
    uint48 internal constant TOKEN_VALUATION_DELAY = 4 days;
    uint48 internal constant TOKEN_SETTLEMENT_DURATION = 30 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        SecuritizeAccount(
            oracle,
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            REDEMPTION_WALLET_ADDRESS,
            TOKEN_INITIAL_CUTOFF,
            TOKEN_INITIAL_CUTOFF_PERIOD,
            TOKEN_VALUATION_DELAY,
            TOKEN_SETTLEMENT_DURATION,
            cowSwapSettlement
        )
    {}
}

contract ACRED_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

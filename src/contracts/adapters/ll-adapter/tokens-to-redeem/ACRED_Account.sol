// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {AcredSecuritizeAccount} from "../SecuritizeAccount.sol";

contract ACRED_Account is AcredSecuritizeAccount {
    address internal constant TOKEN_ADDRESS = 0x17418038ecF73BA4026c4f428547BF099706F27B;
    address internal constant REDEMPTION_WALLET_ADDRESS = 0xbb543C77436645C8b95B64eEc39E3C0d48D4842b;
    uint48 internal constant TOKEN_VALUATION_DELAY = 4 days;
    uint48 internal constant TOKEN_POST_CUTOFF_WINDOW = 30 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        AcredSecuritizeAccount(
            oracle,
            factory,
            TOKEN_ADDRESS,
            REDEMPTION_WALLET_ADDRESS,
            TOKEN_VALUATION_DELAY,
            TOKEN_POST_CUTOFF_WINDOW,
            cowSwapSettlement
        )
    {}
}

contract ACRED_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

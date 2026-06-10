// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SecuritizeAccount} from "../SecuritizeAccount.sol";

contract ACRED_Account is SecuritizeAccount {
    address internal constant TOKEN_ADDRESS = 0x17418038ecF73BA4026c4f428547BF099706F27B;
    uint48 internal constant TOKEN_COOLDOWN = 9 days;
    uint48 internal constant TOKEN_PENDING_ASSETS_DURATION = 90 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        SecuritizeAccount(
            oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, TOKEN_PENDING_ASSETS_DURATION, cowSwapSettlement
        )
    {}
}

contract ACRED_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

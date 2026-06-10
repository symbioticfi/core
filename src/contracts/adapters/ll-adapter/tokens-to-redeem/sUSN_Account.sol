// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {NoonAccount} from "../NoonAccount.sol";

contract sUSN_Account is NoonAccount {
    address internal constant TOKEN_ADDRESS = 0xE24a3DC889621612422A64E6388927901608B91D;
    address internal constant WITHDRAWAL_HANDLER_ADDRESS = 0x0DaBc0D9B270c9B0C4C77AaCeAa712b56D0F9178;
    uint48 internal constant TOKEN_COOLDOWN = 17 hours;

    constructor(address oracle, address factory, address cowSwapSettlement)
        NoonAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, WITHDRAWAL_HANDLER_ADDRESS, cowSwapSettlement)
    {}
}

contract sUSN_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

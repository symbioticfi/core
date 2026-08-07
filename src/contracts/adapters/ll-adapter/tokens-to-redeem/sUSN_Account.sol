// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {NoonAccount} from "../NoonAccount.sol";
import {NoonOracle} from "../oracles/NoonOracle.sol";

contract sUSN_Account is NoonAccount {
    uint256 internal constant MIN_PRICE = 0.5e18;
    uint256 internal constant MAX_PRICE = 2.5e18;
    address internal constant TOKEN_ADDRESS = 0xE24a3DC889621612422A64E6388927901608B91D;
    address internal constant WITHDRAWAL_HANDLER_ADDRESS = 0x0DaBc0D9B270c9B0C4C77AaCeAa712b56D0F9178;
    address internal constant RATE_PROVIDER_ADDRESS = 0x7f741401422Afff770360fD13127F7462C6E1A79;
    uint48 internal constant TOKEN_COOLDOWN = 17 hours;

    constructor(address factory, address cowSwapSettlement)
        NoonAccount(
            address(new NoonOracle(MIN_PRICE, MAX_PRICE, RATE_PROVIDER_ADDRESS, TOKEN_ADDRESS)),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            WITHDRAWAL_HANDLER_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract sUSN_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

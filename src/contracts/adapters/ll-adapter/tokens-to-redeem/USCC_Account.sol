// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SuperstateAccount} from "../SuperstateAccount.sol";

contract USCC_Account is SuperstateAccount {
    address internal constant TOKEN_ADDRESS = 0x14d60E7FDC0D71d8611742720E4C50E7a974020c;
    uint48 internal constant TOKEN_COOLDOWN = 12 hours;
    uint48 internal constant TOKEN_SETTLEMENT_DURATION = 3 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        SuperstateAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, TOKEN_SETTLEMENT_DURATION, cowSwapSettlement)
    {}
}

contract USCC_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

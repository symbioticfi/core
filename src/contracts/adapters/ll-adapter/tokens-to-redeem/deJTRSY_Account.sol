// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CentrifugeAccount} from "../CentrifugeAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract deJTRSY_Account is CentrifugeAccount {
    address internal constant TOKEN_ADDRESS = 0xA6233014B9b7aaa74f38fa1977ffC7A89642dC72;
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        CentrifugeAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, cowSwapSettlement)
    {}
}

contract deJTRSY_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

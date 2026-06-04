// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {CentrifugeAccount} from "../CentrifugeAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract ACRDX_Account is CentrifugeAccount {
    address internal constant TOKEN_ADDRESS = 0x9477724Bb54AD5417de8Baff29e59DF3fB4DA74f;
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address asyncRedeemVault, address factory, address oracle)
        CentrifugeAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, asyncRedeemVault)
    {}
}

contract ACRDX_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

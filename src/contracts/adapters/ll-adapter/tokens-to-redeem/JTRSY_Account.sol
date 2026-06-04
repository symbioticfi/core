// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {CentrifugeAccount} from "../CentrifugeAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract JTRSY_Account is CentrifugeAccount {
    address internal constant TOKEN_ADDRESS = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address asyncRedeemVault, address factory, address oracle)
        CentrifugeAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, asyncRedeemVault)
    {}
}

contract JTRSY_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

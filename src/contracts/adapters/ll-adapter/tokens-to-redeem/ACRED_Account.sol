// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {AcredAccount} from "../SecuritizeAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract ACRED_Account is AcredAccount {
    constructor(address factory, address oracle, address tokenToRedeem, address redemptionWallet)
        AcredAccount(factory, oracle, tokenToRedeem, redemptionWallet)
    {}
}

contract ACRED_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

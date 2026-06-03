// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {FigureAccount} from "../FigureAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract PRIME_Account is FigureAccount {
    constructor(address asyncRedeemVault, address tokenToRedeem, address redeemShare, address factory, address oracle)
        FigureAccount(asyncRedeemVault, tokenToRedeem, redeemShare, factory, oracle)
    {}
}

contract PRIME_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

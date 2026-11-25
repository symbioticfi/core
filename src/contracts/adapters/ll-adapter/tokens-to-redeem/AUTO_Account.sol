// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {FigureAccount} from "../FigureAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract AUTO_Account is FigureAccount {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address subAccountImplementation,
        address cowSwapSettlement
    ) FigureAccount(oracle, factory, TOKEN_COOLDOWN, tokenToRedeem, subAccountImplementation, cowSwapSettlement) {}
}

contract AUTO_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {FigureAccount} from "../FigureAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract PRIME_Account is FigureAccount {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address asyncRedeemVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    )
        FigureAccount(
            oracle, factory, TOKEN_COOLDOWN, tokenToRedeem, asyncRedeemVault, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

contract PRIME_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

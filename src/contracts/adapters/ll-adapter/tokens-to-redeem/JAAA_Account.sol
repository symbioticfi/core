// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {CentrifugeAccount} from "../CentrifugeAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract JAAA_Account is CentrifugeAccount {
    address internal constant TOKEN_ADDRESS = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(
        address oracle,
        address factory,
        address asyncRedeemVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    )
        CentrifugeAccount(
            oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, asyncRedeemVault, cowSwapSettlement, cowSwapVaultRelayer
        )
    {}
}

contract JAAA_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

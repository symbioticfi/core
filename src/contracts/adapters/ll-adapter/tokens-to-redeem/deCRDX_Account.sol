// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AsyncRedeemAccount} from "../common/AsyncRedeemAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract deCRDX_Account is AsyncRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x9E2679eABFF131b8b1b48fF7566140794E0eEdc4;
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        AsyncRedeemAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, cowSwapSettlement)
    {}
}

contract deCRDX_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

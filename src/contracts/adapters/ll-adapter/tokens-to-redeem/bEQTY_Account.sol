// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {DigiFTAccount} from "../DigiFTAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract bEQTY_Account is DigiFTAccount {
    address internal constant SUB_RED_MANAGEMENT_ADDRESS = 0x3797C46db697c24a983222c335F17Ba28e8c5b69;
    address internal constant TOKEN_ADDRESS = 0xEaFD6D38f41f882BCFd5fEaABccCc714B983b701;
    uint48 internal constant TOKEN_PENDING_ASSETS_DURATION = 1 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        DigiFTAccount(
            oracle, factory, TOKEN_ADDRESS, SUB_RED_MANAGEMENT_ADDRESS, TOKEN_PENDING_ASSETS_DURATION, cowSwapSettlement
        )
    {}
}

contract bEQTY_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

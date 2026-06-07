// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ThreeJaneAccount} from "../ThreeJaneAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract sUSD3_Account is ThreeJaneAccount {
    address internal constant TOKEN_ADDRESS = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;

    constructor(address oracle, address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        ThreeJaneAccount(oracle, factory, TOKEN_ADDRESS, cowSwapSettlement, cowSwapVaultRelayer)
    {}
}

contract sUSD3_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

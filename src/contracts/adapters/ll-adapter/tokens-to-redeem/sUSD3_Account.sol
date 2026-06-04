// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {ThreeJaneAccount} from "../ThreeJaneAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract sUSD3_Account is ThreeJaneAccount {
    address internal constant TOKEN_ADDRESS = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;

    constructor(address factory, address oracle) ThreeJaneAccount(TOKEN_ADDRESS, factory, oracle) {}
}

contract sUSD3_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

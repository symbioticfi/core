// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {LidoAccount} from "../LidoAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract wstETH_Account is LidoAccount {
    constructor(address factory, address oracle, address wstETH, address stETH, address withdrawalQueue)
        LidoAccount(factory, oracle, wstETH, stETH, withdrawalQueue)
    {}
}

contract wstETH_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

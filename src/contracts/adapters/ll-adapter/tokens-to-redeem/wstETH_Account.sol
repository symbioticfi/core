// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {LidoAccount} from "../LidoAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract wstETH_Account is LidoAccount {
    constructor(
        address stETH,
        address weth,
        address oracle,
        address wstETH,
        address factory,
        address withdrawalQueue,
        address cowSwapSettlement
    ) LidoAccount(stETH, weth, oracle, wstETH, factory, withdrawalQueue, cowSwapSettlement) {}
}

contract wstETH_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

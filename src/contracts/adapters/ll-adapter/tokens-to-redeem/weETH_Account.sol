// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {EtherFiAccount} from "../EtherFiAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract weETH_Account is EtherFiAccount {
    constructor(
        address factory,
        address oracle,
        address weETH,
        address eETH,
        address liquidityPool,
        address redemptionManager,
        address withdrawRequestNft,
        address weth
    ) EtherFiAccount(withdrawRequestNft, redemptionManager, liquidityPool, weETH, factory, oracle, eETH, weth) {}
}

contract weETH_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

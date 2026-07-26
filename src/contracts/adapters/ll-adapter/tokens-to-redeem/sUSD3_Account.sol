// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SThreeJaneAccount} from "../SThreeJaneAccount.sol";

contract sUSD3_Account is SThreeJaneAccount {
    address internal constant TOKEN_ADDRESS = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;

    constructor(address oracle, address factory, address cowSwapSettlement)
        SThreeJaneAccount(oracle, factory, TOKEN_ADDRESS, cowSwapSettlement)
    {}
}

contract sUSD3_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

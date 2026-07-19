// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {ParetoAccount} from "../ParetoAccount.sol";

contract AA_FalconX_Account is ParetoAccount {
    address internal constant TOKEN_ADDRESS = 0xC26A6Fa2C37b38E549a4a1807543801Db684f99C;
    address internal constant WITHDRAWAL_QUEUE_ADDRESS = 0x5cC24f44cCAa80DD2c079156753fc1e908F495DC;

    constructor(address oracle, address factory, address cowSwapSettlement)
        ParetoAccount(oracle, factory, TOKEN_ADDRESS, WITHDRAWAL_QUEUE_ADDRESS, cowSwapSettlement)
    {}
}

contract AA_FalconX_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

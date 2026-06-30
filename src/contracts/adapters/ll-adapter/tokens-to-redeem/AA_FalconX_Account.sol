// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {ParetoAccount} from "../ParetoAccount.sol";

contract AA_FalconX_Account is ParetoAccount {
    address internal constant IDLE_CDO_ADDRESS = 0x433D5B175148dA32Ffe1e1A37a939E1b7e79be4d;
    address internal constant TOKEN_ADDRESS = 0xC26A6Fa2C37b38E549a4a1807543801Db684f99C;
    uint48 internal constant TOKEN_COOLDOWN = 3 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        ParetoAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, IDLE_CDO_ADDRESS, cowSwapSettlement)
    {}
}

contract AA_FalconX_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

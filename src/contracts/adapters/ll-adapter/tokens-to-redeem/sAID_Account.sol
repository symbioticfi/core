// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {GaibAccount} from "../GaibAccount.sol";
import {SaidOracle} from "../oracles/SaidOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract sAID_Account is GaibAccount {
    address internal constant TOKEN_ADDRESS = 0xB3B3c527BA57cd61648e2EC2F5e006A0B390A9F8;
    uint48 internal constant TOKEN_COOLDOWN = 6 days;

    constructor(address factory, address cowSwapSettlement, address cowSwapVaultRelayer)
        GaibAccount(
            address(new SaidOracle(TOKEN_ADDRESS)),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            cowSwapSettlement,
            cowSwapVaultRelayer
        )
    {}
}

contract sAID_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

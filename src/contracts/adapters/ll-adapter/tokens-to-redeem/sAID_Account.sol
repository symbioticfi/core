// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {GaibAccount} from "../GaibAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SaidOracle} from "../oracles/SaidOracle.sol";

contract sAID_Account is GaibAccount {
    address internal constant TOKEN_ADDRESS = 0xB3B3c527BA57cd61648e2EC2F5e006A0B390A9F8;
    uint48 internal constant TOKEN_COOLDOWN = 6 days;

    constructor(address factory, address cowSwapSettlement)
        GaibAccount(
            address(new SaidOracle(527_574_236_280_171_822, 2_110_296_945_120_687_290, TOKEN_ADDRESS)),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract sAID_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

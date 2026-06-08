// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MakinaAccount} from "../MakinaAccount.sol";
import {MakinaOracle} from "../oracles/MakinaOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract DUSD_Account is MakinaAccount {
    address internal constant SHARE_PRICE_ORACLE_ADDRESS = 0xFFCBc7A7eEF2796C277095C66067aC749f4cA078;
    address internal constant REDEEMER_ADDRESS = 0x1303c26cFE06bac5bfEE29907f37919643DEF75c;
    address internal constant TOKEN_ADDRESS = 0x1e33E98aF620F1D563fcD3cfd3C75acE841204ef;
    uint48 internal constant TOKEN_COOLDOWN = 72 minutes;

    constructor(address factory, address cowSwapSettlement)
        MakinaAccount(
            address(new MakinaOracle(SHARE_PRICE_ORACLE_ADDRESS)),
            factory,
            TOKEN_COOLDOWN,
            REDEEMER_ADDRESS,
            TOKEN_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract DUSD_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

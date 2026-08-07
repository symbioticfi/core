// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MakinaAccount} from "../MakinaAccount.sol";
import {MakinaOracle} from "../oracles/MakinaOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract DUSD_Account is MakinaAccount {
    address internal constant SHARE_PRICE_ORACLE_ADDRESS = 0xFFCBc7A7eEF2796C277095C66067aC749f4cA078;
    address internal constant MACHINE_ADDRESS = 0x6b006870C83b1Cd49E766Ac9209f8d68763Df721;
    address internal constant REDEEMER_ADDRESS = 0x1303c26cFE06bac5bfEE29907f37919643DEF75c;
    address internal constant TOKEN_ADDRESS = 0x1e33E98aF620F1D563fcD3cfd3C75acE841204ef;
    uint48 internal constant TOKEN_COOLDOWN = 72 minutes;
    /// @dev Local fail-closed policy for Makina's global accounting updates.
    uint48 internal constant ORACLE_STALENESS_DURATION = 48 hours;

    constructor(address factory, address cowSwapSettlement)
        MakinaAccount(
            address(
                new MakinaOracle(
                    515_533_500_000_000_000,
                    2_062_134_000_000_000_000,
                    SHARE_PRICE_ORACLE_ADDRESS,
                    MACHINE_ADDRESS,
                    ORACLE_STALENESS_DURATION
                )
            ),
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

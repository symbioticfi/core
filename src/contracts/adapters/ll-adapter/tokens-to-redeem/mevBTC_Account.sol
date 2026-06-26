// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MidasCompAccount} from "../MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IMidasTokenAccount} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasTokenAccount.sol";

contract mevBTC_Account is MidasCompAccount, IMidasTokenAccount {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint48 public constant MAX_WITHDRAWAL_DELAY = 7 days;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant TOKEN_ADDRESS = 0xb64C014307622eB15046C66fF71D04258F5963DC;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x2d7d5b1706653796602617350571B3F8999B950c;

    constructor(address factory, address cowSwapSettlement)
        MidasCompAccount(
            address(
                new MidasOracle(
                    511_811_155_000_000_000,
                    2_047_244_620_000_000_000,
                    address(IMidasRedemptionVault(REDEMPTION_VAULT_ADDRESS).mTokenDataFeed())
                )
            ),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            WBTC,
            REDEMPTION_VAULT_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract mevBTC_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

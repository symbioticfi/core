// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MidasCompAccount} from "../MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IMidasTokenAccount} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasTokenAccount.sol";

contract mBTC_Account is MidasCompAccount, IMidasTokenAccount {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint48 public constant MAX_WITHDRAWAL_DELAY = 7 days;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant TOKEN_ADDRESS = 0x007115416AB6c266329a03B09a8aa39aC2eF7d9d;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x30d9D1e76869516AEa980390494AaEd45C3EfC1a;

    constructor(address factory, address cowSwapSettlement)
        MidasCompAccount(
            address(
                new MidasOracle(
                    516_201_565_000_000_000,
                    2_064_806_260_000_000_000,
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

    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (_asset != WBTC) {
            revert InvalidAsset();
        }
    }
}

contract mBTC_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

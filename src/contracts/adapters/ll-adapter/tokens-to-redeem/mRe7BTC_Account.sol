// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MidasCompAccount} from "../MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IMidasTokenAccount} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasTokenAccount.sol";

contract mRe7BTC_Account is MidasCompAccount, IMidasTokenAccount {
    uint48 internal constant TOKEN_COOLDOWN = 2 days;
    uint48 public constant MAX_WITHDRAWAL_DELAY = 24 days;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant TOKEN_ADDRESS = 0x9FB442d6B612a6dcD2acC67bb53771eF1D9F661A;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x4Fd4DD7171D14e5bD93025ec35374d2b9b4321b0;

    constructor(address factory, address cowSwapSettlement)
        MidasCompAccount(
            address(new MidasOracle(address(IMidasRedemptionVault(REDEMPTION_VAULT_ADDRESS).mTokenDataFeed()))),
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

contract mRe7BTC_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

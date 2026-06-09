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
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant TOKEN_ADDRESS = 0xb64C014307622eB15046C66fF71D04258F5963DC;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x2d7d5b1706653796602617350571B3F8999B950c;

    constructor(address factory, address cowSwapSettlement)
        MidasCompAccount(
            address(new MidasOracle(address(IMidasRedemptionVault(REDEMPTION_VAULT_ADDRESS).mTokenDataFeed()))),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            MAINNET_USDC,
            REDEMPTION_VAULT_ADDRESS,
            cowSwapSettlement
        )
    {}

    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (_asset != MAINNET_USDC) {
            revert InvalidAsset();
        }
    }
}

contract mevBTC_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

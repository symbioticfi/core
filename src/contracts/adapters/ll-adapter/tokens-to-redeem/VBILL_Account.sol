// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ChainlinkOracle} from "../oracles/ChainlinkOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SecuritizeOffRampAccount} from "../SecuritizeOffRampAccount.sol";

contract VBILL_Account is SecuritizeOffRampAccount {
    uint256 internal constant MIN_PRICE = 0.95e18;
    uint256 internal constant MAX_PRICE = 1.05e18;
    address internal constant TOKEN_ADDRESS = 0x2255718832bC9fD3bE1CaF75084F4803DA14FF01;
    address internal constant OFF_RAMP_ADDRESS = 0x1eD617529d80AE87E6611f11D8de8532ECED42bC;
    address internal constant SETTLEMENT_TOKEN_ADDRESS = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    address internal constant NAV_FEED_ADDRESS = 0xA569E68B5D110F2A255482c2997DFDBe1b2ab912;
    uint48 internal constant FEED_STALENESS_DURATION = 30 hours;

    constructor(address factory, address cowSwapSettlement)
        SecuritizeOffRampAccount(
            address(
                new ChainlinkOracle(
                    MIN_PRICE, MAX_PRICE, [NAV_FEED_ADDRESS, address(0)], [FEED_STALENESS_DURATION, uint48(0)]
                )
            ),
            factory,
            TOKEN_ADDRESS,
            OFF_RAMP_ADDRESS,
            SETTLEMENT_TOKEN_ADDRESS,
            cowSwapSettlement
        )
    {}
}

contract VBILL_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

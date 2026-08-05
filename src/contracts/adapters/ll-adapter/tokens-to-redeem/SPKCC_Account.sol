// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ChainlinkOracle} from "../oracles/ChainlinkOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SpikoAccount} from "../SpikoAccount.sol";

contract SPKCC_Account is SpikoAccount {
    uint256 internal constant MIN_PRICE = 0.5e18;
    uint256 internal constant MAX_PRICE = 2e18;
    address internal constant TOKEN_ADDRESS = 0x4f33aCf823E6eEb697180d553cE0c710124C8D59;
    address internal constant REDEMPTION_ADDRESS = 0xDA5599f04e9b437C8394b0c2BC68B502A66ebFe8;
    address internal constant SETTLEMENT_TOKEN_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant NAV_FEED_ADDRESS = 0x9e37DBF40fE5Fe9320E45fe6B95b000aa05459A9;
    uint48 internal constant FEED_STALENESS_DURATION = 30 hours;
    uint48 internal constant TOKEN_SETTLEMENT_DURATION = 30 days;

    constructor(address factory, address cowSwapSettlement)
        SpikoAccount(
            address(
                new ChainlinkOracle(
                    MIN_PRICE, MAX_PRICE, [NAV_FEED_ADDRESS, address(0)], [FEED_STALENESS_DURATION, uint48(0)]
                )
            ),
            factory,
            TOKEN_ADDRESS,
            REDEMPTION_ADDRESS,
            SETTLEMENT_TOKEN_ADDRESS,
            TOKEN_SETTLEMENT_DURATION,
            cowSwapSettlement
        )
    {}
}

contract SPKCC_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

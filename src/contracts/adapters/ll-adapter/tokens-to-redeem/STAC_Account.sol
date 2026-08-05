// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ChainlinkOracle} from "../oracles/ChainlinkOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SecuritizeNoticeAccount} from "../SecuritizeNoticeAccount.sol";

contract STAC_Account is SecuritizeNoticeAccount {
    uint256 internal constant MIN_PRICE = 100e18;
    uint256 internal constant MAX_PRICE = 10_000e18;
    address internal constant TOKEN_ADDRESS = 0x51C2d74017390CbBd30550179A16A1c28F7210fc;
    address internal constant REDEMPTION_WALLET_ADDRESS = 0xbb543C77436645C8b95B64eEc39E3C0d48D4842b;
    address internal constant NAV_FEED_ADDRESS = 0xEdC6287D3D41b322AF600317628D7E226DD3add4;
    uint48 internal constant FEED_STALENESS_DURATION = 30 hours;
    uint48 internal constant TOKEN_SETTLEMENT_DURATION = 30 days;

    constructor(address factory, address cowSwapSettlement)
        SecuritizeNoticeAccount(
            address(
                new ChainlinkOracle(
                    MIN_PRICE, MAX_PRICE, [NAV_FEED_ADDRESS, address(0)], [FEED_STALENESS_DURATION, uint48(0)]
                )
            ),
            factory,
            TOKEN_ADDRESS,
            REDEMPTION_WALLET_ADDRESS,
            TOKEN_SETTLEMENT_DURATION,
            cowSwapSettlement
        )
    {}
}

contract STAC_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

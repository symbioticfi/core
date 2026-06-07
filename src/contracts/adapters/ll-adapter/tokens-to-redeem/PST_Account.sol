// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {HumaAccount} from "../HumaAccount.sol";
import {ChainlinkOracle} from "../oracles/ChainlinkOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract PST_Account is HumaAccount {
    address internal constant CHAINLINK_FEED_ADDRESS = 0x4BE50bE32dB1510240d542f77c5B36Ca0D0965E6;
    address internal constant TOKEN_ADDRESS = 0x22aE3D9a738471f405169Af055d31c687087d4c7;
    uint48 internal constant STALENESS_DURATION = 2 days;

    constructor(address factory, address redemptionVault, address cowSwapSettlement, address cowSwapVaultRelayer)
        HumaAccount(
            address(new ChainlinkOracle([CHAINLINK_FEED_ADDRESS, address(0)], [STALENESS_DURATION, uint48(0)])),
            factory,
            TOKEN_ADDRESS,
            redemptionVault,
            cowSwapSettlement,
            cowSwapVaultRelayer
        )
    {}
}

contract PST_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

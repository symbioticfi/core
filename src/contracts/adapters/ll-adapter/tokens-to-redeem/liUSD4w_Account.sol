// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ChainlinkOracle} from "../oracles/ChainlinkOracle.sol";
import {InfiniFiAccount} from "../InfiniFiAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract liUSD4w_Account is InfiniFiAccount {
    uint48 internal constant TOKEN_COOLDOWN = 3 days;
    /// @dev The bucket feed reports `updatedAt = block.timestamp` on every read, so any positive
    ///      staleness duration passes; 30 days is a generous formality.
    uint48 internal constant FEED_STALENESS_DURATION = 30 days;
    address internal constant TOKEN_ADDRESS = 0x66bCF6151D5558AfB47c38B20663589843156078;
    address internal constant BUCKET_FEED_ADDRESS = 0xF8472D8D3Ef3f8aEb83A2B09aC69f40dF1ace66c;
    address internal constant GATEWAY_ADDRESS = 0x3f04b65Ddbd87f9CE0A2e7Eb24d80e7fb87625b5;
    address internal constant UNWINDING_MODULE_ADDRESS = 0x7092A43aE5407666C78dBEA657a1891f42b3dFcc;
    address internal constant IUSD_ADDRESS = 0x48f9e38f3070AD8945DFEae3FA70987722E3D89c;
    uint32 internal constant UNWINDING_EPOCHS_4W = 4;

    constructor(address factory, address cowSwapSettlement)
        InfiniFiAccount(
            address(new ChainlinkOracle([BUCKET_FEED_ADDRESS, address(0)], [FEED_STALENESS_DURATION, uint48(0)])),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            GATEWAY_ADDRESS,
            UNWINDING_MODULE_ADDRESS,
            IUSD_ADDRESS,
            UNWINDING_EPOCHS_4W,
            cowSwapSettlement
        )
    {}
}

contract liUSD4w_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}

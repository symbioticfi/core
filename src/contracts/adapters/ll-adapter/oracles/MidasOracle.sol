// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {ILiquidLaneOracle} from "../../../../interfaces/adapters/ll-adapter/ILiquidLaneOracle.sol";
import {IMidasDataFeed, IMidasOracle} from "../../../../interfaces/adapters/ll-adapter/oracles/IMidasOracle.sol";

/// @title MidasOracle
/// @notice Midas data-feed oracle returning a token price in `1e18` precision.
contract MidasOracle is IMidasOracle {
    /* IMMUTABLES */

    /// @inheritdoc IMidasOracle
    address public immutable DATA_FEED;

    /* CONSTRUCTOR */

    constructor(address dataFeed) {
        DATA_FEED = dataFeed;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc ILiquidLaneOracle
    function getPrice() public view returns (uint256) {
        return IMidasDataFeed(DATA_FEED).getDataInBase18();
    }
}

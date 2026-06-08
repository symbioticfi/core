// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IMidasDataFeed, IMidasOracle} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasOracle.sol";
import {IOracle} from "../../../../interfaces/adapters/ll-adapter/IOracle.sol";

/// @title MidasOracle
/// @notice Midas data-feed oracle returning a token price in `1e18` precision.
contract MidasOracle is IMidasOracle {
    /* IMMUTABLES */

    /// @inheritdoc IMidasOracle
    address public immutable DATA_FEED;

    /* CONSTRUCTOR */

    /// @notice Creates the Midas data-feed oracle.
    constructor(address dataFeed) {
        DATA_FEED = dataFeed;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IOracle
    function getPrice() public view returns (uint256) {
        return IMidasDataFeed(DATA_FEED).getDataInBase18();
    }
}

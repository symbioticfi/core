// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title ISaidOracle
 * @notice Interface for GAIB sAID loss-aware share-price oracles.
 */
interface ISaidOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the sAID vault used as the price source.
     * @return vault The sAID vault address.
     */
    function VAULT() external view returns (address vault);
}

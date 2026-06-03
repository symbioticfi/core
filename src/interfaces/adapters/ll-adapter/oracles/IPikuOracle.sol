// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IPikuOracle
 * @notice Interface for Piku Accountable vault share-price oracles.
 */
interface IPikuOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the Piku Accountable vault used as the price source.
     * @return vault The vault address.
     */
    function VAULT() external view returns (address vault);
}

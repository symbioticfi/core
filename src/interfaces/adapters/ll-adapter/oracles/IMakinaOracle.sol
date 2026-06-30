// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IMakinaOracle
 * @notice Interface for Makina Machine share-price oracle adapters.
 */
interface IMakinaOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the Makina share-price oracle.
     * @return oracle The share-price oracle address.
     */
    function SHARE_PRICE_ORACLE() external view returns (address oracle);
}

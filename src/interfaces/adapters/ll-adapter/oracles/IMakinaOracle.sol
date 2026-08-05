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

    /**
     * @notice Returns the Makina Machine whose accounting timestamp gates the price.
     * @return machine The Machine address.
     */
    function MACHINE() external view returns (address machine);

    /**
     * @notice Returns the maximum age of the Machine accounting state.
     * @return duration The permitted age in seconds.
     */
    function STALENESS_DURATION() external view returns (uint48 duration);
}

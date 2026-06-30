// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPriceDataOracle} from "../IPriceDataOracle.sol";

/**
 * @title IAssetoOracle
 * @notice Interface for Asseto pricer-backed liquidity lane oracles.
 */
interface IAssetoOracle is IPriceDataOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the Asseto pricer contract.
     * @return pricer The pricer address.
     */
    function PRICER() external view returns (address pricer);
}

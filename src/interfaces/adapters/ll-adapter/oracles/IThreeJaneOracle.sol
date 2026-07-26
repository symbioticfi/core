// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IThreeJaneOracle
 * @notice Interface for Three Jane USD3 redemption-price oracles.
 */
interface IThreeJaneOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the USD3 token whose redemption price is reported.
     * @return token The USD3 token address.
     */
    function TOKEN_TO_REDEEM() external view returns (address token);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IThreeJaneOracle
 * @notice Interface for Three Jane sUSD3 redemption-price oracles.
 */
interface IThreeJaneOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the sUSD3 token whose redemption price is reported.
     * @return token The sUSD3 token address.
     */
    function TOKEN_TO_REDEEM() external view returns (address token);

    /**
     * @notice Returns the USD3 vault redeemed by sUSD3.
     * @return vault The USD3 vault address.
     */
    function USD3() external view returns (address vault);
}

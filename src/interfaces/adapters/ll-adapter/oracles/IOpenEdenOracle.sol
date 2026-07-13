// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IOpenEdenOracle
 * @notice Interface for OpenEden HYBOND redemption-price oracles.
 */
interface IOpenEdenOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the token whose redemption price is reported.
     * @return token The token-to-redeem address.
     */
    function TOKEN_TO_REDEEM() external view returns (address token);

    /**
     * @notice Returns the OpenEden express redemption contract.
     * @return express The express redemption contract address.
     */
    function EXPRESS() external view returns (address express);
}

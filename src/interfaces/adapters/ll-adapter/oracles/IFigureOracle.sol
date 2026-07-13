// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IFigureOracle
 * @notice Interface for Figure/Hastra redemption-price oracles.
 */
interface IFigureOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the token whose redemption price is reported.
     * @return token The token-to-redeem address.
     */
    function TOKEN_TO_REDEEM() external view returns (address token);

    /**
     * @notice Returns the nested async redeem vault.
     * @return vault The async redeem vault address.
     */
    function ASYNC_REDEEM_VAULT() external view returns (address vault);
}

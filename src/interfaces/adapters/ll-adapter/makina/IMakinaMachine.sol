// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMakinaMachine
 * @notice Interface for Makina Machine data used by liquidity lane accounts.
 */
interface IMakinaMachine {
    /* FUNCTIONS */

    /**
     * @notice Returns the Machine accounting token.
     * @return token The accounting token address.
     */
    function accountingToken() external view returns (address token);
}

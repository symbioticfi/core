// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILidoAccount
 * @notice Interface for Lido liquidity lane accounts.
 */
interface ILidoAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the stETH token address.
     * @return stETH The stETH token address.
     */
    function STETH() external view returns (address stETH);

    /**
     * @notice Returns the wstETH token address.
     * @return wstETH The wstETH token address.
     */
    function WSTETH() external view returns (address wstETH);
}

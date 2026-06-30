// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IWeETH
 * @notice Minimal ether.fi weETH interface used by liquidity lane accounts.
 */
interface IWeETH {
    /**
     * @notice Unwraps weETH into eETH.
     * @param weETHAmount The weETH amount.
     * @return eETHAmount The resulting eETH amount.
     */
    function unwrap(uint256 weETHAmount) external returns (uint256 eETHAmount);

    /**
     * @notice Converts weETH amount to eETH amount.
     * @param weETHAmount The weETH amount.
     * @return eETHAmount The resulting eETH amount.
     */
    function getEETHByWeETH(uint256 weETHAmount) external view returns (uint256 eETHAmount);
}

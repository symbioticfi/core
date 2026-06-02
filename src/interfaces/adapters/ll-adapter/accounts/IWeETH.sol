// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IWeETH
 * @notice Minimal ether.fi weETH interface used by liquidity lane accounts.
 */
interface IWeETH {
    function unwrap(uint256 weETHAmount) external returns (uint256 eETHAmount);

    function getEETHByWeETH(uint256 weETHAmount) external view returns (uint256 eETHAmount);
}

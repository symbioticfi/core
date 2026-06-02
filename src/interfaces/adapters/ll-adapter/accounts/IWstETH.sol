// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IWstETH
 * @notice Minimal Lido wstETH interface used by liquidity lane accounts.
 */
interface IWstETH {
    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount);

    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount);

    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256 wstETHAmount);

    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256 stETHAmount);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IWstETH
 * @notice Minimal Lido wstETH interface used by liquidity lane accounts.
 */
interface IWstETH {
    /**
     * @notice Wraps stETH into wstETH.
     * @param stETHAmount The stETH amount.
     * @return wstETHAmount The resulting wstETH amount.
     */
    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount);

    /**
     * @notice Unwraps wstETH into stETH.
     * @param wstETHAmount The wstETH amount.
     * @return stETHAmount The resulting stETH amount.
     */
    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount);

    /**
     * @notice Converts stETH amount to wstETH amount.
     * @param stETHAmount The stETH amount.
     * @return wstETHAmount The resulting wstETH amount.
     */
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256 wstETHAmount);

    /**
     * @notice Converts wstETH amount to stETH amount.
     * @param wstETHAmount The wstETH amount.
     * @return stETHAmount The resulting stETH amount.
     */
    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256 stETHAmount);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEtherFiLiquidityPool
 * @notice Minimal ether.fi liquidity pool interface used by weETH accounts.
 */
interface IEtherFiLiquidityPool {
    function requestWithdraw(address recipient, uint256 amount) external returns (uint256 requestId);
}

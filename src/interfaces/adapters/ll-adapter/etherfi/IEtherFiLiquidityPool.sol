// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEtherFiLiquidityPool
 * @notice Minimal ether.fi liquidity pool interface used by weETH accounts.
 */
interface IEtherFiLiquidityPool {
    /**
     * @notice Requests an ether.fi withdrawal.
     * @param recipient The withdrawal recipient.
     * @param amount The eETH amount to withdraw.
     * @return requestId The created withdrawal request id.
     */
    function requestWithdraw(address recipient, uint256 amount) external returns (uint256 requestId);

    /**
     * @notice Returns the eETH amount represented by shares.
     * @param share The eETH share amount.
     * @return amount The eETH amount.
     */
    function amountForShare(uint256 share) external view returns (uint256 amount);
}

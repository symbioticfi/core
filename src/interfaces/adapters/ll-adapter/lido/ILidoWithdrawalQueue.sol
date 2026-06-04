// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILidoWithdrawalQueue
 * @notice Minimal Lido withdrawal queue interface used by liquidity lane accounts.
 */
interface ILidoWithdrawalQueue {
    /**
     * @notice Returns the maximum stETH amount allowed per withdrawal request.
     * @return amount The maximum request amount.
     */
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256 amount);

    /**
     * @notice Returns the minimum stETH amount allowed per withdrawal request.
     * @return amount The minimum request amount.
     */
    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256 amount);

    /**
     * @notice Requests stETH withdrawals.
     * @param amounts The stETH amounts to withdraw.
     * @param recipient The withdrawal NFT recipient.
     * @return requestIds The withdrawal request ids.
     */
    function requestWithdrawals(uint256[] calldata amounts, address recipient)
        external
        returns (uint256[] memory requestIds);

    /**
     * @notice Requests wstETH withdrawals.
     * @param amounts The wstETH amounts to withdraw.
     * @param recipient The withdrawal NFT recipient.
     * @return requestIds The withdrawal request ids.
     */
    function requestWithdrawalsWstETH(uint256[] calldata amounts, address recipient)
        external
        returns (uint256[] memory requestIds);

    /**
     * @notice Claims a finalized withdrawal request.
     * @param requestId The withdrawal request id.
     */
    function claimWithdrawal(uint256 requestId) external;
}

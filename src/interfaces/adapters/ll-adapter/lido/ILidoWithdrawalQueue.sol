// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILidoWithdrawalQueue
 * @notice Minimal Lido withdrawal queue interface used by liquidity lane accounts.
 */
interface ILidoWithdrawalQueue {
    /**
     * @notice Lido withdrawal request status.
     * @param amountOfStETH The stETH amount submitted for withdrawal.
     * @param amountOfShares The Lido shares submitted for withdrawal.
     * @param owner The withdrawal NFT owner.
     * @param timestamp The request creation timestamp.
     * @param isFinalized True if the request is finalized.
     * @param isClaimed True if the request is claimed.
     */
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

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
     * @notice Returns statuses for withdrawal requests.
     * @param requestIds The withdrawal request ids.
     * @return statuses The withdrawal request statuses.
     */
    function getWithdrawalStatus(uint256[] calldata requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);

    /**
     * @notice Returns the latest withdrawal queue checkpoint index.
     * @return index The latest checkpoint index.
     */
    function getLastCheckpointIndex() external view returns (uint256 index);

    /**
     * @notice Finds checkpoint hints for sorted withdrawal request ids.
     * @param requestIds The sorted withdrawal request ids.
     * @param firstIndex The first checkpoint index to search.
     * @param lastIndex The last checkpoint index to search.
     * @return hints The checkpoint hints.
     */
    function findCheckpointHints(uint256[] calldata requestIds, uint256 firstIndex, uint256 lastIndex)
        external
        view
        returns (uint256[] memory hints);

    /**
     * @notice Returns claimable ETH for withdrawal request ids.
     * @param requestIds The withdrawal request ids.
     * @param hints The checkpoint hints.
     * @return amounts The claimable ETH amounts.
     */
    function getClaimableEther(uint256[] calldata requestIds, uint256[] calldata hints)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Claims a finalized withdrawal request.
     * @param requestId The withdrawal request id.
     */
    function claimWithdrawal(uint256 requestId) external;
}

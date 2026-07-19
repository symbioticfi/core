// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IParetoWithdrawalQueue
 * @notice Interface for Pareto epoch withdrawal queues.
 */
interface IParetoWithdrawalQueue {
    /**
     * @notice Claims a processed withdrawal epoch for the caller.
     * @param epoch The processing epoch.
     */
    function claimWithdrawRequest(uint256 epoch) external;

    /**
     * @notice Returns underlyings still awaiting protocol settlement for an epoch.
     * @param epoch The processing epoch.
     * @return assets The unsettled underlying amount.
     */
    function epochPendingClaims(uint256 epoch) external view returns (uint256 assets);

    /**
     * @notice Returns the fixed underlying price for a processed withdrawal epoch.
     * @param epoch The processing epoch.
     * @return price The underlying amount per `1e18` tranche units, or zero before processing.
     */
    function epochWithdrawPrice(uint256 epoch) external view returns (uint256 price);

    /**
     * @notice Returns the CDO served by the queue.
     * @return idleCdo The CDO address.
     */
    function idleCDOEpoch() external view returns (address idleCdo);

    /**
     * @notice Submits tranche tokens for withdrawal in the next epoch.
     * @param amount The tranche-token amount.
     */
    function requestWithdraw(uint256 amount) external;

    /**
     * @notice Returns the credit vault served by the queue.
     * @return creditVault The credit-vault address.
     */
    function strategy() external view returns (address creditVault);

    /**
     * @notice Returns the tranche token accepted by the queue.
     * @return token The tranche-token address.
     */
    function tranche() external view returns (address token);

    /**
     * @notice Returns the underlying token paid by the queue.
     * @return token The underlying-token address.
     */
    function underlying() external view returns (address token);

    /**
     * @notice Returns an account's queued tranche tokens for an epoch.
     * @param account The requesting account.
     * @param epoch The processing epoch.
     * @return amount The queued tranche-token amount.
     */
    function userWithdrawalsEpochs(address account, uint256 epoch) external view returns (uint256 amount);
}

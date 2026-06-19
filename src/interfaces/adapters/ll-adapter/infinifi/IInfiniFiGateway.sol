// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IInfiniFiGateway
 * @notice Interface for the infiniFi gateway user entry point.
 */
interface IInfiniFiGateway {
    /* FUNCTIONS */

    /**
     * @notice Redeems iUSD for the underlying asset at the protocol oracle rate.
     * @dev Pulls iUSD from the caller. Pays instantly when the redeem controller holds idle
     *      liquidity and its queue is empty, otherwise enqueues a FIFO redemption ticket for `to`
     *      and returns less than the full value (0 when fully enqueued). Reverts while protocol
     *      losses are unaccrued.
     * @param to The asset recipient and queue ticket beneficiary.
     * @param amount The iUSD amount to redeem.
     * @param minAssetsOut The minimum accepted instant asset payout.
     * @return assetsOut The instantly paid asset amount.
     */
    function redeem(address to, uint256 amount, uint256 minAssetsOut) external returns (uint256 assetsOut);

    /**
     * @notice Burns locked iUSD shares and opens an unwinding position for the caller.
     * @dev Pulls liUSD from the caller. The position is keyed by the caller and `block.timestamp`,
     *      so a caller cannot open two positions in the same second.
     * @param shares The liUSD share amount to unwind.
     * @param unwindingEpochs The bucket's unwinding duration in epochs.
     */
    function startUnwinding(uint256 shares, uint32 unwindingEpochs) external;

    /**
     * @notice Pays out a completed unwinding position in iUSD to the caller.
     * @dev Reverts while the position is still unwinding or while protocol losses are unaccrued.
     * @param unwindingTimestamp The position's start timestamp.
     */
    function withdraw(uint256 unwindingTimestamp) external;
}

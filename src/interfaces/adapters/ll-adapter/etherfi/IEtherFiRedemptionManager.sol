// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEtherFiRedemptionManager
 * @notice Minimal ether.fi instant redemption manager interface used by weETH accounts.
 */
interface IEtherFiRedemptionManager {
    /**
     * @notice Instant-redemption bucket config.
     */
    struct BucketLimit {
        /// @notice Bucket capacity.
        uint64 capacity;
        /// @notice Remaining bucket capacity.
        uint64 remaining;
        /// @notice Last refill timestamp.
        uint64 lastRefill;
        /// @notice Bucket refill rate.
        uint64 refillRate;
    }

    /**
     * @notice Returns the ETH sentinel address.
     * @return token The ETH sentinel address.
     */
    function ETH_ADDRESS() external view returns (address token);

    /**
     * @notice Returns whether instant redemption is available.
     * @param amount The amount to redeem.
     * @param token The requested output token.
     * @return status Whether redemption is available.
     */
    function canRedeem(uint256 amount, address token) external view returns (bool status);

    /**
     * @notice Instantly redeems weETH into the requested output token.
     * @param weETHAmount The weETH amount to redeem.
     * @param receiver The redemption receiver.
     * @param outputToken The requested output token.
     */
    function redeemWeEth(uint256 weETHAmount, address receiver, address outputToken) external;

    /**
     * @notice Returns redemption info for an output token.
     * @param token The output token.
     * @return limit The bucket limit.
     * @return exitFeeSplitToTreasuryInBps The treasury fee split.
     * @return exitFeeInBps The exit fee.
     * @return lowWatermarkInBpsOfTvl The low watermark.
     */
    function tokenToRedemptionInfo(address token)
        external
        view
        returns (
            BucketLimit memory limit,
            uint16 exitFeeSplitToTreasuryInBps,
            uint16 exitFeeInBps,
            uint16 lowWatermarkInBpsOfTvl
        );
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEtherFiRedemptionManager
 * @notice Minimal ether.fi instant redemption manager interface used by weETH accounts.
 */
interface IEtherFiRedemptionManager {
    struct BucketLimit {
        uint64 capacity;
        uint64 remaining;
        uint64 lastRefill;
        uint64 refillRate;
    }

    function ETH_ADDRESS() external view returns (address token);

    function canRedeem(uint256 amount, address token) external view returns (bool status);

    function redeemWeEth(uint256 weETHAmount, address receiver, address outputToken) external;

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

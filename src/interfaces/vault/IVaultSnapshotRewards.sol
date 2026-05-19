// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVaultSnapshotRewards
 * @notice Minimal interface for vault snapshot reward claims.
 */
interface IVaultSnapshotRewards {
    /* STRUCTS */

    /**
     * @notice Snapshot of a vault reward distribution.
     * @param subnetworkId Identifier of the subnetwork the reward targets.
     * @param delegator Delegator contract responsible for distribution.
     * @param delegatorType Type identifier that classifies the delegator.
     * @param timestamp Block timestamp when the reward was recorded.
     * @param amount Reward amount allocated to stakers.
     * @param operatorsFees Portion of the reward reserved for operators.
     */
    struct RewardDistribution {
        uint96 subnetworkId;
        address delegator;
        uint64 delegatorType;
        uint48 timestamp;
        uint256 amount;
        uint256 operatorsFees;
    }

    /* FUNCTIONS */

    /**
     * @notice Returns the number of reward distributions for a vault, network, and token.
     * @param vault The vault address.
     * @param network The network address.
     * @param token The token address.
     * @return length Number of reward distributions.
     */
    function rewardsLength(address vault, address network, address token) external view returns (uint256 length);

    /**
     * @notice Returns a reward distribution by index.
     * @param vault The vault address.
     * @param network The network address.
     * @param token The token address.
     * @param index The reward index.
     * @return distribution Reward distribution data.
     */
    function rewards(address vault, address network, address token, uint256 index)
        external
        view
        returns (RewardDistribution memory distribution);

    /**
     * @notice Returns the last unclaimed reward index for an account.
     * @param account The account address.
     * @param vault The vault address.
     * @param network The network address.
     * @param token The token address.
     * @return rewardIndex Last unclaimed reward index.
     */
    function lastUnclaimedReward(address account, address vault, address network, address token)
        external
        view
        returns (uint256 rewardIndex);

    /**
     * @notice Claims vault snapshot rewards.
     * @param recipient The recipient address.
     * @param network The network address.
     * @param token The token address.
     * @param vault The vault address.
     * @param lastUnclaimedRewards The last unclaimed rewards index.
     * @param firstRewardToClaim The first reward index to claim.
     * @param rewardsToClaim The maximum number of rewards to process.
     * @param activeSharesOfHints Hints for active shares calculation.
     */
    function claimVaultSnapshotRewards(
        address recipient,
        address network,
        address token,
        address vault,
        uint256 lastUnclaimedRewards,
        uint256 firstRewardToClaim,
        uint256 rewardsToClaim,
        bytes[] memory activeSharesOfHints
    ) external;
}

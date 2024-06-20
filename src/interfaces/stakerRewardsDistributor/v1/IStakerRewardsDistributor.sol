// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IStakerRewardsDistributor {
    /**
     * @notice Emitted when a reward is distributed.
     * @param network network on behalf of which the reward is distributed
     * @param token address of the token
     * @param amount amount of tokens
     * @param timestamp time point stakes must be taken into account at
     */
    event DistributeReward(address indexed network, address indexed token, uint256 amount, uint48 timestamp);

    /**
     * @notice Get a version of the rewards distributor (different versions mean different interfaces).
     * @return version of the rewards distributor
     * @dev Must return 1 for this one.
     */
    function version() external view returns (uint64);

    /**
     * @notice Distribute rewards on behalf of a particular network using a given token.
     * @param network network on behalf of which the reward to distribute
     * @param token address of the token
     * @param amount amount of tokens
     * @param timestamp time point stakes must be taken into account at
     */
    function distributeReward(address network, address token, uint256 amount, uint48 timestamp) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRewardsDistributorBase} from "./IRewardsDistributorBase.sol";

interface IRewardsDistributor is IRewardsDistributorBase {
    /**
     * @notice Emitted when a reward is distributed.
     * @param token address of the token to be distributed
     * @param network network on behalf of which the reward is distributed
     * @param amount amount of tokens distributed
     * @param timestamp time point stakes must taken into account at
     */
    event DistributeReward(address indexed token, address indexed network, uint256 amount, uint48 timestamp);

    /**
     * @notice Distribute rewards on behalf of a particular network using a given token.
     * @param network address of the network
     * @param token address of the token
     * @param amount amount of tokens to distribute
     * @param timestamp time point stakes must taken into account at
     */
    function distributeReward(address network, address token, uint256 amount, uint48 timestamp) external;
}

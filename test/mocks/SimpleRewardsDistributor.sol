// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRewardsDistributor} from "src/interfaces/base/rewardsDistributor/v1/IRewardsDistributor.sol";

contract SimpleRewardsDistributor is IRewardsDistributor {
    /**
     * @inheritdoc IRewardsDistributor
     */
    uint64 public constant version = 1;

    /**
     * @inheritdoc IRewardsDistributor
     */
    function distributeReward(address network, address token, uint256 amount, uint48 timestamp) external {
        emit DistributeReward(network, token, amount, timestamp);
    }
}

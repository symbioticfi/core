// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IStakerRewardsDistributor} from "src/interfaces/stakerRewardsDistributor/IStakerRewardsDistributor.sol";

contract SimpleRewardsDistributor is IStakerRewardsDistributor {
    /**
     * @inheritdoc IStakerRewardsDistributor
     */
    uint64 public constant version = 1;

    /**
     * @inheritdoc IStakerRewardsDistributor
     */
    function distributeReward(address network, address token, uint256 amount, uint48 timestamp) external {
        emit DistributeReward(network, token, amount, timestamp);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RewardsDistributorBase} from "./RewardsDistributorBase.sol";

import {IRewardsDistributorBase} from "src/interfaces/base/IRewardsDistributorBase.sol";
import {IRewardsDistributor} from "src/interfaces/base/IRewardsDistributor.sol";

abstract contract RewardsDistributor is RewardsDistributorBase, IRewardsDistributor {
    constructor(address networkRegistry) RewardsDistributorBase(networkRegistry) {}

    /**
     * @inheritdoc IRewardsDistributorBase
     */
    function version() external pure override(RewardsDistributorBase, IRewardsDistributorBase) returns (uint64) {
        return 1;
    }

    /**
     * @inheritdoc IRewardsDistributor
     */
    function distributeReward(address network, address token, uint256 amount, uint48 timestamp) external virtual {}
}

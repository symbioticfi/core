// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RewardsDistributorBase} from "src/contracts/base/RewardsDistributorBase.sol";
import {RewardsDistributor} from "src/contracts/base/RewardsDistributor.sol";

import {IRewardsDistributorBase} from "src/interfaces/base/IRewardsDistributorBase.sol";
import {IRewardsDistributor} from "src/interfaces/base/IRewardsDistributor.sol";

contract SimpleRewardsDistributor is RewardsDistributor {
    constructor(address networkRegistry) RewardsDistributor(networkRegistry) {}

    /**
     * @inheritdoc IRewardsDistributorBase
     */
    function VAULT() public pure override(RewardsDistributorBase, IRewardsDistributorBase) returns (address) {
        return address(1);
    }

    /**
     * @inheritdoc IRewardsDistributor
     */
    function distributeReward(
        address network,
        address token,
        uint256 amount,
        uint48 timestamp
    ) external override checkNetwork(network) {
        emit DistributeReward(network, token, amount, timestamp);
    }
}

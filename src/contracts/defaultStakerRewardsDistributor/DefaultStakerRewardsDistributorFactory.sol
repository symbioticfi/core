// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DefaultStakerRewardsDistributor} from "./DefaultStakerRewardsDistributor.sol";
import {Registry} from "src/contracts/common/Registry.sol";

import {IDefaultStakerRewardsDistributorFactory} from
    "src/interfaces/defaultStakerRewardsDistributor/IDefaultStakerRewardsDistributorFactory.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract DefaultStakerRewardsDistributorFactory is Registry, IDefaultStakerRewardsDistributorFactory {
    using Clones for address;

    address private immutable STAKER_REWARDS_DISTRIBUTOR_IMPLEMENTATION;

    constructor(address rewardsDistributorImplementation) {
        STAKER_REWARDS_DISTRIBUTOR_IMPLEMENTATION = rewardsDistributorImplementation;
    }

    /**
     * @inheritdoc IDefaultStakerRewardsDistributorFactory
     */
    function create(address vault) external returns (address) {
        address stakerRewardsDistributor = STAKER_REWARDS_DISTRIBUTOR_IMPLEMENTATION.clone();
        DefaultStakerRewardsDistributor(stakerRewardsDistributor).initialize(vault);

        _addEntity(stakerRewardsDistributor);

        return stakerRewardsDistributor;
    }
}

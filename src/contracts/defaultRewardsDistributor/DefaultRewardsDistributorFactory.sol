// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DefaultRewardsDistributor} from "./DefaultRewardsDistributor.sol";
import {Registry} from "src/contracts/base/Registry.sol";

import {IDefaultRewardsDistributorFactory} from
    "src/interfaces/defaultRewardsDistributor/IDefaultRewardsDistributorFactory.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract DefaultRewardsDistributorFactory is Registry, IDefaultRewardsDistributorFactory {
    using Clones for address;

    address private immutable REWARDS_DISTRIBUTOR_IMPLEMENTATION;

    constructor(address networkRegistry, address vaultFactory, address networkMiddlewareService) {
        REWARDS_DISTRIBUTOR_IMPLEMENTATION =
            address(new DefaultRewardsDistributor(networkRegistry, vaultFactory, networkMiddlewareService));
    }

    /**
     * @inheritdoc IDefaultRewardsDistributorFactory
     */
    function create(address vault) external returns (address) {
        address rewardsDistributor = REWARDS_DISTRIBUTOR_IMPLEMENTATION.clone();
        DefaultRewardsDistributor(rewardsDistributor).initialize(vault);

        _addEntity(rewardsDistributor);

        return rewardsDistributor;
    }
}

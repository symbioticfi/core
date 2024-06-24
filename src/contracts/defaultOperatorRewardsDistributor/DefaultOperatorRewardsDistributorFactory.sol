// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DefaultOperatorRewardsDistributor} from "./DefaultOperatorRewardsDistributor.sol";
import {Registry} from "src/contracts/common/Registry.sol";

import {IDefaultOperatorRewardsDistributorFactory} from
    "src/interfaces/defaultOperatorRewardsDistributor/IDefaultOperatorRewardsDistributorFactory.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract DefaultOperatorRewardsDistributorFactory is Registry, IDefaultOperatorRewardsDistributorFactory {
    using Clones for address;

    address private immutable OPERATOR_REWARDS_DISTRIBUTOR_IMPLEMENTATION;

    constructor(address operatorRewardsDistributorImplementation) {
        OPERATOR_REWARDS_DISTRIBUTOR_IMPLEMENTATION = operatorRewardsDistributorImplementation;
    }

    /**
     * @inheritdoc IDefaultOperatorRewardsDistributorFactory
     */
    function create(address vault) external returns (address) {
        address operatorRewardsDistributor = OPERATOR_REWARDS_DISTRIBUTOR_IMPLEMENTATION.clone();
        DefaultOperatorRewardsDistributor(operatorRewardsDistributor).initialize(vault);

        _addEntity(operatorRewardsDistributor);

        return operatorRewardsDistributor;
    }
}

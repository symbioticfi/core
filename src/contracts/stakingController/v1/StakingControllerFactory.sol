// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {StakingController} from "./StakingController.sol";
import {Registry} from "src/contracts/base/Registry.sol";

import {IStakingControllerFactory} from "src/interfaces/stakingController/v1/IStakingControllerFactory.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract StakingControllerFactory is Registry, IStakingControllerFactory {
    using Clones for address;

    address private immutable STAKING_CONTROLLER_IMPLEMENTATION;

    constructor(
        address networkRegistry,
        address vaultFactory,
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService
    ) {
        STAKING_CONTROLLER_IMPLEMENTATION = address(
            new StakingController(
                vaultFactory,
                networkRegistry,
                networkMiddlewareService,
                networkVaultOptInService,
                operatorVaultOptInService,
                operatorNetworkOptInService
            )
        );
    }

    /**
     * @inheritdoc IStakingControllerFactory
     */
    function create(address vault, uint48 vetoDuration, uint48 executeDuration) external returns (address) {
        address stakingController = STAKING_CONTROLLER_IMPLEMENTATION.clone();
        StakingController(stakingController).initialize(vault, vetoDuration, executeDuration);

        _addEntity(stakingController);

        return stakingController;
    }
}

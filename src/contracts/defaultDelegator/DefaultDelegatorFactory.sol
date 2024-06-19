// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DefaultDelegator} from "./DefaultDelegator.sol";
import {Registry} from "src/contracts/base/Registry.sol";

import {IDefaultDelegatorFactory} from "src/interfaces/defaultDelegator/IDefaultDelegatorFactory.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract DefaultDelegatorFactory is Registry, IDefaultDelegatorFactory {
    using Clones for address;

    address private immutable DELEGATOR_IMPLEMENTATION;

    constructor(address delegatorImplementation) {
        DELEGATOR_IMPLEMENTATION = delegatorImplementation;
    }

    /**
     * @inheritdoc IDefaultDelegatorFactory
     */
    function create(address networkResolverDelegator, address operatorNetworkDelegator) external returns (address) {
        address delegator = DELEGATOR_IMPLEMENTATION.clone();
        DefaultDelegator(delegator).initialize(networkResolverDelegator, operatorNetworkDelegator);
        _addEntity(delegator);

        return delegator;
    }
}

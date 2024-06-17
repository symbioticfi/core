// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DefaultLimiter} from "./DefaultLimiter.sol";
import {Registry} from "src/contracts/base/Registry.sol";

import {IDefaultLimiterFactory} from "src/interfaces/defaultLimiter/IDefaultLimiterFactory.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract DefaultLimiterFactory is Registry, IDefaultLimiterFactory {
    using Clones for address;

    address private immutable LIMITER_IMPLEMENTATION;

    constructor(address networkRegistry, address vaultFactory) {
        LIMITER_IMPLEMENTATION = address(new DefaultLimiter(networkRegistry, vaultFactory));
    }

    /**
     * @inheritdoc IDefaultLimiterFactory
     */
    function create(address networkResolverLimiter, address operatorNetworkLimiter) external returns (address) {
        address limiter = LIMITER_IMPLEMENTATION.clone();
        DefaultLimiter(limiter).initialize(networkResolverLimiter, operatorNetworkLimiter);
        _addEntity(limiter);

        return limiter;
    }
}

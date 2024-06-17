// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "src/interfaces/base/IRegistry.sol";

interface IDefaultLimiterFactory is IRegistry {
    /**
     * @notice Create a default limiter.
     */
    function create(address networkResolverLimiter, address operatorNetworkLimiter) external returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "src/interfaces/base/IRegistry.sol";

interface IDefaultDelegatorFactory is IRegistry {
    /**
     * @notice Create a default delegator.
     */
    function create(address networkResolverDelegator, address operatorNetworkDelegator) external returns (address);
}

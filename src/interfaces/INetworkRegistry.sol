// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "./base/IRegistry.sol";

interface INetworkRegistry is IRegistry {
    error NetworkAlreadyRegistered();

    /**
     * @notice Register the caller as a network.
     */
    function registerNetwork() external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRegistry} from "./common/IRegistry.sol";

/**
 * @title INetworkRegistry
 * @notice Interface for the NetworkRegistry contract.
 */
interface INetworkRegistry is IRegistry {
    error NetworkAlreadyRegistered();

    /**
     * @notice Register the caller as a network.
     */
    function registerNetwork() external;
}

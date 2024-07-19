// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IRegistry} from "./common/IRegistry.sol";

interface INetworkRegistry is IRegistry {
    error NetworkAlreadyRegistered();

    /**
     * @notice Register the caller as a network.
     */
    function registerNetwork() external;
}

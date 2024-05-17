// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "./IRegistry.sol";

interface INonMigratablesRegistry is IRegistry {
    error EntityAlreadyRegistered();

    /**
     * @notice Register a new entity at the registry.
     */
    function register() external;
}

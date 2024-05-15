// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFactory} from "./IFactory.sol";

interface INonMigratablesRegistry is IFactory {
    error EntityAlreadyRegistered();

    /**
     * @notice Register a new entity at the registry.
     */
    function register() external;
}

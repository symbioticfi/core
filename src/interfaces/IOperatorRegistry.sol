// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "./base/IRegistry.sol";

interface IOperatorRegistry is IRegistry {
    error OperatorAlreadyRegistered();

    /**
     * @notice Register the caller as an operator.
     */
    function registerOperator() external;
}

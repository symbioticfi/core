// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRegistry} from "./common/IRegistry.sol";

/**
 * @title IOperatorRegistry
 * @notice Interface for the OperatorRegistry contract.
 */
interface IOperatorRegistry is IRegistry {
    error OperatorAlreadyRegistered();

    /**
     * @notice Register the caller as an operator.
     */
    function registerOperator() external;
}

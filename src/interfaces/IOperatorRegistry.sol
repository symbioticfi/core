// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IRegistry} from "./common/IRegistry.sol";

interface IOperatorRegistry is IRegistry {
    error OperatorAlreadyRegistered();

    /**
     * @notice Register the caller as an operator.
     */
    function registerOperator() external;
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Registry} from "./common/Registry.sol";

import {IOperatorRegistry} from "src/interfaces/IOperatorRegistry.sol";

contract OperatorRegistry is Registry, IOperatorRegistry {
    /**
     * @inheritdoc IOperatorRegistry
     */
    function registerOperator() external {
        if (isEntity(msg.sender)) {
            revert OperatorAlreadyRegistered();
        }

        _addEntity(msg.sender);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IOperatorOptInPlugin} from "src/interfaces/plugins/IOperatorOptInPlugin.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

import {Plugin} from "src/contracts/base/Plugin.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract OperatorOptInPlugin is Plugin, IOperatorOptInPlugin {
    /**
     * @inheritdoc IOperatorOptInPlugin
     */
    address public immutable WHERE_REGISTRY;

    /**
     * @inheritdoc IOperatorOptInPlugin
     */
    mapping(address operator => mapping(address where => bool value)) public isOptedIn;

    /**
     * @inheritdoc IOperatorOptInPlugin
     */
    mapping(address operator => mapping(address where => uint48 timestamp)) public lastOptOut;

    constructor(address operatorRegistry, address whereRegistry) Plugin(operatorRegistry) {
        WHERE_REGISTRY = whereRegistry;
    }

    /**
     * @inheritdoc IOperatorOptInPlugin
     */
    function wasOptedIn(address operator, address where, uint256 edgeTimestamp) external view returns (bool) {
        return isOptedIn[operator][where] || lastOptOut[operator][where] >= edgeTimestamp;
    }

    /**
     * @inheritdoc IOperatorOptInPlugin
     */
    function optIn(address where) external onlyEntity {
        if (!IRegistry(WHERE_REGISTRY).isEntity(where)) {
            revert NotWhereEntity();
        }

        if (isOptedIn[msg.sender][where]) {
            revert AlreadyOptedIn();
        }

        isOptedIn[msg.sender][where] = true;

        emit OptIn(msg.sender, where);
    }

    /**
     * @inheritdoc IOperatorOptInPlugin
     */
    function optOut(address where) external {
        if (!isOptedIn[msg.sender][where]) {
            revert NotOptedIn();
        }

        isOptedIn[msg.sender][where] = false;
        lastOptOut[msg.sender][where] = Time.timestamp();

        emit OptOut(msg.sender, where);
    }
}

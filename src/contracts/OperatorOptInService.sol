// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IOperatorOptInService} from "src/interfaces/IOperatorOptInService.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract OperatorOptInService is IOperatorOptInService {
    /**
     * @inheritdoc IOperatorOptInService
     */
    address public immutable OPERATOR_REGISTRY;

    /**
     * @inheritdoc IOperatorOptInService
     */
    address public immutable WHERE_REGISTRY;

    /**
     * @inheritdoc IOperatorOptInService
     */
    mapping(address operator => mapping(address where => bool value)) public isOptedIn;

    /**
     * @inheritdoc IOperatorOptInService
     */
    mapping(address operator => mapping(address where => uint48 timestamp)) public lastOptOut;

    constructor(address operatorRegistry, address whereRegistry) {
        OPERATOR_REGISTRY = operatorRegistry;
        WHERE_REGISTRY = whereRegistry;
    }

    /**
     * @inheritdoc IOperatorOptInService
     */
    function wasOptedInAfter(address operator, address where, uint48 timestamp) external view returns (bool) {
        return isOptedIn[operator][where] || lastOptOut[operator][where] >= timestamp;
    }

    /**
     * @inheritdoc IOperatorOptInService
     */
    function optIn(address where) external {
        if (!IRegistry(OPERATOR_REGISTRY).isEntity(msg.sender)) {
            revert NotOperator();
        }

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
     * @inheritdoc IOperatorOptInService
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

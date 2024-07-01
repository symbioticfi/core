// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IOptInService} from "src/interfaces/service/IOptInService.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract OptInService is IOptInService {
    /**
     * @inheritdoc IOptInService
     */
    address public immutable WHO_REGISTRY;

    /**
     * @inheritdoc IOptInService
     */
    address public immutable WHERE_REGISTRY;

    /**
     * @inheritdoc IOptInService
     */
    mapping(address who => mapping(address where => bool value)) public isOptedIn;

    /**
     * @inheritdoc IOptInService
     */
    mapping(address who => mapping(address where => uint48 timestamp)) public lastOptOut;

    constructor(address whoRegistry, address whereRegistry) {
        WHO_REGISTRY = whoRegistry;
        WHERE_REGISTRY = whereRegistry;
    }

    /**
     * @inheritdoc IOptInService
     */
    function wasOptedInAfter(address who, address where, uint48 timestamp) external view returns (bool) {
        return isOptedIn[who][where] || lastOptOut[who][where] >= timestamp;
    }

    /**
     * @inheritdoc IOptInService
     */
    function optIn(address where) external {
        if (!IRegistry(WHO_REGISTRY).isEntity(msg.sender)) {
            revert NotWho();
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
     * @inheritdoc IOptInService
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

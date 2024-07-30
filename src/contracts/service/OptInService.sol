// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "src/contracts/common/StaticDelegateCallable.sol";

import {IOptInService} from "src/interfaces/service/IOptInService.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract OptInService is StaticDelegateCallable, IOptInService {
    using Checkpoints for Checkpoints.Trace208;

    /**
     * @inheritdoc IOptInService
     */
    address public immutable WHO_REGISTRY;

    /**
     * @inheritdoc IOptInService
     */
    address public immutable WHERE_REGISTRY;

    mapping(address who => mapping(address where => Checkpoints.Trace208 value)) internal _isOptedIn;

    constructor(address whoRegistry, address whereRegistry) {
        WHO_REGISTRY = whoRegistry;
        WHERE_REGISTRY = whereRegistry;
    }

    /**
     * @inheritdoc IOptInService
     */
    function isOptedInAt(
        address who,
        address where,
        uint48 timestamp,
        bytes calldata hint
    ) external view returns (bool) {
        return _isOptedIn[who][where].upperLookupRecent(timestamp, hint) == 1;
    }

    /**
     * @inheritdoc IOptInService
     */
    function isOptedIn(address who, address where) public view returns (bool) {
        return _isOptedIn[who][where].latest() == 1;
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

        if (isOptedIn(msg.sender, where)) {
            revert AlreadyOptedIn();
        }

        _isOptedIn[msg.sender][where].push(Time.timestamp(), 1);

        emit OptIn(msg.sender, where);
    }

    /**
     * @inheritdoc IOptInService
     */
    function optOut(address where) external {
        (, uint48 latestTimestamp, uint208 latestValue) = _isOptedIn[msg.sender][where].latestCheckpoint();

        if (latestValue == 0) {
            revert NotOptedIn();
        }

        if (latestTimestamp == Time.timestamp()) {
            revert OptOutCooldown();
        }

        _isOptedIn[msg.sender][where].push(Time.timestamp(), 0);

        emit OptOut(msg.sender, where);
    }
}

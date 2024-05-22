// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IOptInPlugin} from "src/interfaces/plugins/IOptInPlugin.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

import {Plugin} from "src/contracts/base/Plugin.sol";
import {ERC6372} from "src/contracts/utils/ERC6372.sol";

contract OptInPlugin is Plugin, ERC6372, IOptInPlugin {
    /**
     * @inheritdoc IOptInPlugin
     */
    address public immutable WHERE_REGISTRY;

    /**
     * @inheritdoc IOptInPlugin
     */
    mapping(address who => mapping(address where => bool value)) public isOptedIn;

    /**
     * @inheritdoc IOptInPlugin
     */
    mapping(address who => mapping(address where => uint48 timestamp)) public lastOptOut;

    constructor(address whoRegistry, address whereRegistry) Plugin(whoRegistry) {
        WHERE_REGISTRY = whereRegistry;
    }

    /**
     * @inheritdoc IOptInPlugin
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
     * @inheritdoc IOptInPlugin
     */
    function optOut(address where) external {
        if (!isOptedIn[msg.sender][where]) {
            revert NotOptedIn();
        }

        isOptedIn[msg.sender][where] = false;
        lastOptOut[msg.sender][where] = clock();

        emit OptOut(msg.sender, where);
    }
}

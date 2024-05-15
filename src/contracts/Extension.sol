// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IExtension} from "src/interfaces/IExtension.sol";
import {IFactory} from "src/interfaces/IFactory.sol";

contract Extension is IExtension {
    /**
     * @inheritdoc IExtension
     */
    address public immutable REGISTRY;

    modifier onlyEntity() {
        if (!IFactory(REGISTRY).isEntity(msg.sender)) {
            revert NotEntity();
        }
        _;
    }

    constructor(address registry) {
        REGISTRY = registry;
    }
}

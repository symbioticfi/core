// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {INonMigratableEntity} from "src/interfaces/base/INonMigratableEntity.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract NonMigratableEntity is Initializable, INonMigratableEntity {
    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc INonMigratableEntity
     */
    function initialize(bytes memory data) external initializer {
        _initialize(data);
    }

    function _initialize(bytes memory) internal virtual {}
}

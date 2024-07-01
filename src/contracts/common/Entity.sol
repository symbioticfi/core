// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IEntity} from "src/interfaces/common/IEntity.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract Entity is Initializable, IEntity {
    /**
     * @inheritdoc IEntity
     */
    address public immutable FACTORY;

    constructor(address factory) {
        _disableInitializers();

        FACTORY = factory;
    }

    /**
     * @inheritdoc IEntity
     */
    function initialize(bytes memory data) external initializer {
        _initialize(data);
    }

    function _initialize(bytes memory) internal virtual {}
}

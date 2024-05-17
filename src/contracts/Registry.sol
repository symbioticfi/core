// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "src/interfaces/IRegistry.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract Registry is IRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _entities;

    modifier checkEntity(address entity_) {
        if (!isEntity(entity_)) {
            revert EntityNotExist();
        }
        _;
    }

    /**
     * @inheritdoc IRegistry
     */
    function isEntity(address entity_) public view override returns (bool) {
        return _entities.contains(entity_);
    }

    /**
     * @inheritdoc IRegistry
     */
    function totalEntities() public view override returns (uint256) {
        return _entities.length();
    }

    /**
     * @inheritdoc IRegistry
     */
    function entity(uint256 index) public view override returns (address) {
        return _entities.at(index);
    }

    function _addEntity(address entity_) internal {
        _entities.add(entity_);

        emit AddEntity(entity_);
    }
}
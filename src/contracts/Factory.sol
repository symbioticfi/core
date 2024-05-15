// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFactory} from "src/interfaces/IFactory.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract Factory is IFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _entities;

    modifier checkEntity(address entity_) {
        if (!isEntity(entity_)) {
            revert EntityNotExist();
        }
        _;
    }

    /**
     * @inheritdoc IFactory
     */
    function isEntity(address entity_) public view override returns (bool) {
        return _entities.contains(entity_);
    }

    /**
     * @inheritdoc IFactory
     */
    function totalEntities() public view override returns (uint256) {
        return _entities.length();
    }

    /**
     * @inheritdoc IFactory
     */
    function entity(uint256 index) public view override returns (address) {
        return _entities.at(index);
    }

    function _addEntity(address entity_) internal {
        _entities.add(entity_);

        emit AddEntity(entity_);
    }
}

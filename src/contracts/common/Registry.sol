// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {IRegistry} from "../../interfaces/common/IRegistry.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Registry
/// @notice Base contract for generic entity set management.
abstract contract Registry is IRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _entities;

    modifier checkEntity(address account) {
        _checkEntity(account);
        _;
    }

    /// @inheritdoc IRegistry
    function isEntity(address entity_) public view returns (bool) {
        return _entities.contains(entity_);
    }

    /// @inheritdoc IRegistry
    function totalEntities() public view returns (uint256) {
        return _entities.length();
    }

    /// @inheritdoc IRegistry
    function entity(uint256 index) public view returns (address) {
        return _entities.at(index);
    }

    /// @dev Adds an entity to the registry set and emits the registration event.
    function _addEntity(address entity_) internal {
        _entities.add(entity_);

        emit AddEntity(entity_);
    }

    /// @dev Reverts when an account is not registered as an entity.
    function _checkEntity(address account) internal view {
        if (!isEntity(account)) {
            revert EntityNotExist();
        }
    }
}

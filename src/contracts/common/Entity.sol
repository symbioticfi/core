// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {IEntity} from "../../interfaces/common/IEntity.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Entity
/// @notice Base contract for entity type and factory binding.
abstract contract Entity is Initializable, IEntity {
    /// @inheritdoc IEntity
    address public immutable FACTORY;

    /// @inheritdoc IEntity
    uint64 public immutable TYPE;

    constructor(address factory, uint64 type_) {
        _disableInitializers();

        FACTORY = factory;
        TYPE = type_;
    }

    /// @inheritdoc IEntity
    function initialize(bytes calldata data) external initializer {
        _initialize(data);
    }

    /// @dev Initialization hook for entity implementations.
    function _initialize(
        bytes calldata /* data */
    )
        internal
        virtual {}
}

// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title MigratableEntity
/// @notice Base contract for controlled upgradeable entity migration lifecycle.
abstract contract MigratableEntity is Initializable, OwnableUpgradeable, ReentrancyGuard, IMigratableEntity {
    /// @inheritdoc IMigratableEntity
    address public immutable FACTORY;

    modifier notInitialized() {
        if (_getInitializedVersion() != 0) {
            revert AlreadyInitialized();
        }

        _;
    }

    constructor(address factory) {
        _disableInitializers();

        FACTORY = factory;
    }

    /// @inheritdoc IMigratableEntity
    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IMigratableEntity
    function initialize(uint64 initialVersion, address owner_, bytes calldata data)
        external
        notInitialized
        reinitializer(initialVersion)
    {
        if (owner_ != address(0)) {
            __Ownable_init(owner_);
        }

        _initialize(initialVersion, owner_, data);
    }

    /// @inheritdoc IMigratableEntity
    function migrate(uint64 newVersion, bytes calldata data) external nonReentrant {
        if (msg.sender != FACTORY) {
            revert NotFactory();
        }

        _migrateInternal(_getInitializedVersion(), newVersion, data);
    }

    function _migrateInternal(uint64 oldVersion, uint64 newVersion, bytes calldata data)
        private
        reinitializer(newVersion)
    {
        _migrate(oldVersion, newVersion, data);
    }

    /// @dev Initialization hook for migratable entity implementations.
    function _initialize(
        uint64,
        /* initialVersion */
        address,
        /* owner */
        bytes memory /* data */
    )
        internal
        virtual {}

    /// @dev Migration hook for versioned implementation-specific state changes.
    function _migrate(
        uint64,
        /* oldVersion */
        uint64,
        /* newVersion */
        bytes calldata /* data */
    )
        internal
        virtual {}

    uint256[10] private __gap;
}

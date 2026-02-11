// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {MigratableEntityProxy} from "./MigratableEntityProxy.sol";
import {Registry} from "./Registry.sol";

import {IMigratableEntityProxy} from "../../interfaces/common/IMigratableEntityProxy.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {IMigratablesFactory} from "../../interfaces/common/IMigratablesFactory.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MigratablesFactory
/// @notice Factory contract for versioned entity deployment and migration.
contract MigratablesFactory is Registry, Ownable, IMigratablesFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IMigratablesFactory
    mapping(uint64 version => bool value) public blacklisted;

    EnumerableSet.AddressSet private _whitelistedImplementations;

    modifier checkVersion(uint64 version) {
        if (version == 0 || version > lastVersion()) {
            revert InvalidVersion();
        }
        _;
    }

    constructor(address owner_) Ownable(owner_) {}

    /// @inheritdoc IMigratablesFactory
    function lastVersion() public view returns (uint64) {
        return uint64(_whitelistedImplementations.length());
    }

    /// @inheritdoc IMigratablesFactory
    function implementation(uint64 version) public view checkVersion(version) returns (address) {
        return _whitelistedImplementations.at(version - 1);
    }

    /// @inheritdoc IMigratablesFactory
    function whitelist(address implementation_) external onlyOwner {
        if (IMigratableEntity(implementation_).FACTORY() != address(this)) {
            revert InvalidImplementation();
        }
        if (!_whitelistedImplementations.add(implementation_)) {
            revert AlreadyWhitelisted();
        }

        emit Whitelist(implementation_);
    }

    /// @inheritdoc IMigratablesFactory
    function blacklist(uint64 version) external onlyOwner checkVersion(version) {
        if (blacklisted[version]) {
            revert AlreadyBlacklisted();
        }

        blacklisted[version] = true;

        emit Blacklist(version);
    }

    /// @inheritdoc IMigratablesFactory
    function create(uint64 version, address owner_, bytes calldata data) external returns (address entity_) {
        entity_ = address(
            new MigratableEntityProxy{salt: keccak256(abi.encode(totalEntities(), version, owner_, data))}(
                implementation(version), abi.encodeCall(IMigratableEntity.initialize, (version, owner_, data))
            )
        );

        _addEntity(entity_);
    }

    /// @inheritdoc IMigratablesFactory
    function migrate(address entity_, uint64 newVersion, bytes calldata data) external checkEntity(entity_) {
        if (msg.sender != Ownable(entity_).owner()) {
            revert NotOwner();
        }

        if (newVersion <= IMigratableEntity(entity_).version()) {
            revert OldVersion();
        }

        IMigratableEntityProxy(entity_)
            .upgradeToAndCall(implementation(newVersion), abi.encodeCall(IMigratableEntity.migrate, (newVersion, data)));

        emit Migrate(entity_, newVersion);
    }
}

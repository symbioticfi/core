// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMigratablesRegistry} from "src/interfaces/IMigratablesRegistry.sol";
import {IMigratableEntity} from "src/interfaces/IMigratableEntity.sol";

import {Registry} from "./Registry.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MigratablesRegistry is Registry, Ownable, IMigratablesRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _whitelistedImplementations;

    modifier isValidVersion(uint64 version) {
        if (version == 0 || version > lastVersion()) {
            revert InvalidVersion();
        }
        _;
    }

    constructor(address owner_) Ownable(owner_) {}

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function lastVersion() public view returns (uint64) {
        return uint64(_whitelistedImplementations.length());
    }

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function implementation(uint64 version) public view isValidVersion(version) returns (address) {
        return _whitelistedImplementations.at(version - 1);
    }

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function whitelist(address entityImplementation) external onlyOwner {
        if (!_whitelistedImplementations.add(entityImplementation)) {
            revert AlreadyWhitelisted();
        }
    }

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function create(uint64 version, bytes memory data) external isValidVersion(version) returns (address entity_) {
        entity_ = address(
            new ERC1967Proxy(
                implementation(version), abi.encodeWithSelector(IMigratableEntity.initialize.selector, version, data)
            )
        );

        _addEntity(entity_);
    }

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function migrate(address entity_, bytes memory data) external checkEntity(entity_) {
        if (msg.sender != Ownable(entity_).owner()) {
            revert NotOwner();
        }

        UUPSUpgradeable(entity_).upgradeToAndCall(
            implementation(IMigratableEntity(entity_).version() + 1),
            abi.encodeWithSelector(IMigratableEntity.migrate.selector, data)
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratableEntityProxy} from "./MigratableEntityProxy.sol";
import {Registry} from "./Registry.sol";

import {IMigratableEntityProxy} from "src/interfaces/base/IMigratableEntityProxy.sol";
import {IMigratableEntity} from "src/interfaces/base/IMigratableEntity.sol";
import {IMigratablesFactory} from "src/interfaces/base/IMigratablesFactory.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MigratablesFactory is Registry, Ownable, IMigratablesFactory {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;

    EnumerableSet.AddressSet private _whitelistedImplementations;

    modifier isValidVersion(uint64 version) {
        if (version == 0 || version > lastVersion()) {
            revert InvalidVersion();
        }
        _;
    }

    constructor(address owner_) Ownable(owner_) {}

    /**
     * @inheritdoc IMigratablesFactory
     */
    function lastVersion() public view returns (uint64) {
        return uint64(_whitelistedImplementations.length());
    }

    /**
     * @inheritdoc IMigratablesFactory
     */
    function implementation(uint64 version) public view isValidVersion(version) returns (address) {
        return _whitelistedImplementations.at(version - 1);
    }

    /**
     * @inheritdoc IMigratablesFactory
     */
    function whitelist(address entityImplementation) external onlyOwner {
        if (!_whitelistedImplementations.add(entityImplementation)) {
            revert AlreadyWhitelisted();
        }
    }

    /**
     * @inheritdoc IMigratablesFactory
     */
    function create(uint64 version, bytes memory data) external returns (address entity_) {
        entity_ = address(
            new MigratableEntityProxy(
                implementation(version), abi.encodeWithSelector(IMigratableEntity.initialize.selector, version, data)
            )
        );

        _addEntity(entity_);
    }

    /**
     * @inheritdoc IMigratablesFactory
     */
    function migrate(address entity_, bytes memory data) external checkEntity(entity_) {
        if (msg.sender != Ownable(entity_).owner()) {
            revert NotOwner();
        }

        IMigratableEntityProxy(entity_).upgradeToAndCall(
            implementation(IMigratableEntity(entity_).version() + 1),
            abi.encodeWithSelector(IMigratableEntity.migrate.selector, data)
        );
    }
}

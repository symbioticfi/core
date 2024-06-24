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
    function implementation(uint64 version) public view returns (address) {
        if (version == 0 || version > lastVersion()) {
            revert InvalidVersion();
        }
        return _whitelistedImplementations.at(version - 1);
    }

    /**
     * @inheritdoc IMigratablesFactory
     */
    function whitelist(address newImplementation) external onlyOwner {
        if (!_whitelistedImplementations.add(newImplementation)) {
            revert AlreadyWhitelisted();
        }
    }

    /**
     * @inheritdoc IMigratablesFactory
     */
    function create(uint64 version, address owner_, bytes memory data) external returns (address entity_) {
        entity_ = address(
            new MigratableEntityProxy{salt: keccak256(abi.encode(totalEntities(), owner_))}(
                implementation(version),
                abi.encodeWithSelector(IMigratableEntity.initialize.selector, version, owner_, data)
            )
        );

        _addEntity(entity_);
    }

    /**
     * @inheritdoc IMigratablesFactory
     */
    function migrate(address entity_, uint64 newVersion, bytes memory data) external checkEntity(entity_) {
        if (msg.sender != Ownable(entity_).owner()) {
            revert NotOwner();
        }

        if (newVersion <= IMigratableEntity(entity_).version()) {
            revert OldVersion();
        }

        IMigratableEntityProxy(entity_).upgradeToAndCall(
            implementation(newVersion), abi.encodeWithSelector(IMigratableEntity.migrate.selector, newVersion, data)
        );
    }
}

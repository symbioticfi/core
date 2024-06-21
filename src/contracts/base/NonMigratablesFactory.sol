// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Registry} from "./Registry.sol";

import {INonMigratableEntity} from "src/interfaces/base/INonMigratableEntity.sol";
import {INonMigratablesFactory} from "src/interfaces/base/INonMigratablesFactory.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract NonMigratablesFactory is Registry, Ownable, INonMigratablesFactory {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Clones for address;

    EnumerableSet.AddressSet private _whitelistedImplementations;

    constructor(address owner_) Ownable(owner_) {}

    /**
     * @inheritdoc INonMigratablesFactory
     */
    function totalImplementations() public view returns (uint64) {
        return uint64(_whitelistedImplementations.length());
    }

    /**
     * @inheritdoc INonMigratablesFactory
     */
    function implementation(uint64 index) public view returns (address) {
        return _whitelistedImplementations.at(index);
    }

    /**
     * @inheritdoc INonMigratablesFactory
     */
    function whitelist(address implementation_) external onlyOwner {
        if (!_whitelistedImplementations.add(implementation_)) {
            revert AlreadyWhitelisted();
        }
    }

    /**
     * @inheritdoc INonMigratablesFactory
     */
    function create(uint64 index, bytes memory data) external returns (address entity_) {
        entity_ = implementation(index).clone();
        INonMigratableEntity(entity_).initialize(data);

        _addEntity(entity_);
    }
}

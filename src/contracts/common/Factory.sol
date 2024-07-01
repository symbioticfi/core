// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Registry} from "./Registry.sol";

import {IEntity} from "src/interfaces/common/IEntity.sol";
import {IFactory} from "src/interfaces/common/IFactory.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract Factory is Registry, Ownable, IFactory {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Clones for address;

    EnumerableSet.AddressSet private _whitelistedImplementations;

    constructor(address owner_) Ownable(owner_) {}

    /**
     * @inheritdoc IFactory
     */
    function totalImplementations() public view returns (uint64) {
        return uint64(_whitelistedImplementations.length());
    }

    /**
     * @inheritdoc IFactory
     */
    function implementation(uint64 index) public view returns (address) {
        return _whitelistedImplementations.at(index);
    }

    /**
     * @inheritdoc IFactory
     */
    function whitelist(address implementation_) external onlyOwner {
        if (IEntity(implementation_).FACTORY() != address(this)) {
            revert InvalidImplementation();
        }
        if (!_whitelistedImplementations.add(implementation_)) {
            revert AlreadyWhitelisted();
        }
    }

    /**
     * @inheritdoc IFactory
     */
    function create(uint64 index, bytes memory data) external returns (address entity_) {
        entity_ = implementation(index).clone();
        IEntity(entity_).initialize(data);

        _addEntity(entity_);
    }
}

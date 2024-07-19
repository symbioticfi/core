// SPDX-License-Identifier: BUSL-1.1
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
    function totalTypes() public view returns (uint64) {
        return uint64(_whitelistedImplementations.length());
    }

    /**
     * @inheritdoc IFactory
     */
    function implementation(uint64 type_) public view returns (address) {
        return _whitelistedImplementations.at(type_);
    }

    /**
     * @inheritdoc IFactory
     */
    function whitelist(address implementation_) external onlyOwner {
        if (IEntity(implementation_).FACTORY() != address(this) || IEntity(implementation_).TYPE() != totalTypes()) {
            revert InvalidImplementation();
        }
        if (!_whitelistedImplementations.add(implementation_)) {
            revert AlreadyWhitelisted();
        }
    }

    /**
     * @inheritdoc IFactory
     */
    function create(uint64 type_, bool withInitialize, bytes calldata data) external returns (address entity_) {
        entity_ = implementation(type_).cloneDeterministic(keccak256(abi.encode(totalEntities(), type_, data)));

        _addEntity(entity_);

        if (withInitialize) {
            IEntity(entity_).initialize(data);
        }
    }
}

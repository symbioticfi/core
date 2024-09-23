// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Registry} from "./Registry.sol";

import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IFactory} from "../../interfaces/common/IFactory.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Factory is Registry, Ownable, IFactory {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Clones for address;

    /**
     * @inheritdoc IFactory
     */
    mapping(uint64 type_ => bool value) public blacklisted;

    EnumerableSet.AddressSet private _whitelistedImplementations;

    modifier checkType(
        uint64 type_
    ) {
        if (type_ >= totalTypes()) {
            revert InvalidType();
        }
        _;
    }

    constructor(
        address owner_
    ) Ownable(owner_) {}

    /**
     * @inheritdoc IFactory
     */
    function totalTypes() public view returns (uint64) {
        return uint64(_whitelistedImplementations.length());
    }

    /**
     * @inheritdoc IFactory
     */
    function implementation(
        uint64 type_
    ) public view returns (address) {
        return _whitelistedImplementations.at(type_);
    }

    /**
     * @inheritdoc IFactory
     */
    function whitelist(
        address implementation_
    ) external onlyOwner {
        if (IEntity(implementation_).FACTORY() != address(this) || IEntity(implementation_).TYPE() != totalTypes()) {
            revert InvalidImplementation();
        }
        if (!_whitelistedImplementations.add(implementation_)) {
            revert AlreadyWhitelisted();
        }

        emit Whitelist(implementation_);
    }

    /**
     * @inheritdoc IFactory
     */
    function blacklist(
        uint64 type_
    ) external onlyOwner checkType(type_) {
        if (blacklisted[type_]) {
            revert AlreadyBlacklisted();
        }

        blacklisted[type_] = true;

        emit Blacklist(type_);
    }

    /**
     * @inheritdoc IFactory
     */
    function create(uint64 type_, bytes calldata data) external returns (address entity_) {
        entity_ = implementation(type_).cloneDeterministic(keccak256(abi.encode(totalEntities(), type_, data)));

        _addEntity(entity_);

        IEntity(entity_).initialize(data);
    }
}

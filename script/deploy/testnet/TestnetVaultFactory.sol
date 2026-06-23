// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MigratableEntityProxy} from "../../../src/contracts/common/MigratableEntityProxy.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";

import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {IMigratablesFactory} from "../../../src/interfaces/common/IMigratablesFactory.sol";

contract TestnetVaultFactory is VaultFactory {
    constructor(address owner_) VaultFactory(owner_) {}

    function create(uint64 version, address owner_, bytes calldata data)
        public
        override(MigratablesFactory, IMigratablesFactory)
        returns (address entity_)
    {
        entity_ = address(
            new MigratableEntityProxy{salt: keccak256(abi.encode(totalEntities(), version, owner_, data))}(
                implementation(version), abi.encodeCall(IMigratableEntity.initialize, (version, owner_, data))
            )
        );
        _addEntity(entity_);
    }
}

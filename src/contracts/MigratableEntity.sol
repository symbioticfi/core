// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMigratableEntityProxy} from "src/interfaces/IMigratableEntityProxy.sol";
import {IMigratableEntity} from "src/interfaces/IMigratableEntity.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract MigratableEntity is IMigratableEntity, Initializable, OwnableUpgradeable {
    using Address for address;

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function initialize(bytes memory data) public virtual initializer {
        address owner = abi.decode(data, (address));
        __Ownable_init(owner);
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function migrate(bytes memory) public virtual reinitializer(_getInitializedVersion() + 1) {
        address proxyAdmin = abi.decode(
            address(this).functionStaticCall(abi.encodeWithSelector(IMigratableEntityProxy.proxyAdmin.selector)),
            (address)
        );
        if (msg.sender != proxyAdmin) {
            revert NotProxyAdmin();
        }
    }
}

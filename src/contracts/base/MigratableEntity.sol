// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMigratableEntityProxy} from "src/interfaces/base/IMigratableEntityProxy.sol";
import {IMigratableEntity} from "src/interfaces/base/IMigratableEntity.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract MigratableEntity is Initializable, OwnableUpgradeable, IMigratableEntity {
    using Address for address;

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function initialize(uint64 version_, bytes memory data) public virtual reinitializer(version_) {
        address owner = abi.decode(data, (address));
        _initialize(owner);
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function migrate(bytes memory) public virtual reinitializer(_getInitializedVersion() + 1) {
        _migrate();
    }

    function _initialize(address owner) internal {
        __Ownable_init(owner);
    }

    function _migrate() internal view {
        address proxyAdmin = abi.decode(
            address(this).functionStaticCall(abi.encodeWithSelector(IMigratableEntityProxy.proxyAdmin.selector)),
            (address)
        );
        if (msg.sender != proxyAdmin) {
            revert NotProxyAdmin();
        }
    }
}

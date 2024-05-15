// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMigratablesRegistry} from "src/interfaces/IMigratablesRegistry.sol";
import {IMigratableEntityProxy} from "src/interfaces/IMigratableEntityProxy.sol";

import {MigratableEntityProxy} from "./MigratableEntityProxy.sol";
import {MigratableEntity} from "./MigratableEntity.sol";
import {Factory} from "./Factory.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MigratablesRegistry is Factory, Ownable, IMigratablesRegistry {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _whitelistedImplementations;

    mapping(address entity => uint256 version) _versions;

    constructor(address owner_) Ownable(owner_) {}

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function version(address entity_) external view override checkEntity(entity_) returns (uint256) {
        return _versions[entity_];
    }

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function maxVersion() public view override returns (uint256) {
        return _whitelistedImplementations.length();
    }

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function whitelist(address entityImplementation) external override onlyOwner {
        if (!_whitelistedImplementations.add(entityImplementation)) {
            revert AlreadyWhitelisted();
        }
    }

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function migrate(address entity_, bytes memory data) external checkEntity(entity_) {
        if (msg.sender != MigratableEntity(entity_).owner()) {
            revert ImproperOwner();
        }

        uint256 currentVersion = _versions[entity_];
        uint256 newestVersion = _whitelistedImplementations.length();
        if (currentVersion == newestVersion) {
            revert AlreadyUpToDate();
        }

        _versions[entity_] = currentVersion + 1;

        address proxyAdmin = abi.decode(
            entity_.functionStaticCall(abi.encodeWithSelector(IMigratableEntityProxy.proxyAdmin.selector)), (address)
        );
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(entity_),
            _whitelistedImplementations.at(currentVersion),
            abi.encodeWithSelector(MigratableEntity.migrate.selector, data)
        );
    }

    function create(uint256 version_, bytes memory data) external returns (address entity_) {
        uint256 maxVersion_ = maxVersion();
        if (version_ == 0 || version_ > maxVersion_) {
            revert InvalidVersion();
        }

        entity_ = address(
            new MigratableEntityProxy(
                _whitelistedImplementations.at(version_ - 1),
                address(this),
                abi.encodeWithSelector(MigratableEntity.initialize.selector, data)
            )
        );

        _addEntity(entity_);
        _versions[entity_] = version_;
    }
}

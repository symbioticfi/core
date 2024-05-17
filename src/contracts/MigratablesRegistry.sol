// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMigratablesRegistry} from "src/interfaces/IMigratablesRegistry.sol";

import {MigratableEntity} from "./MigratableEntity.sol";
import {Registry} from "./Registry.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MigratablesRegistry is Registry, Ownable, IMigratablesRegistry {
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
    function create(uint256 version_, bytes memory data) external returns (address entity_) {
        uint256 maxVersion_ = maxVersion();
        if (version_ == 0 || version_ > maxVersion_) {
            revert InvalidVersion();
        }

        entity_ = address(
            new ERC1967Proxy(
                _whitelistedImplementations.at(version_ - 1),
                abi.encodeWithSelector(MigratableEntity.initialize.selector, data)
            )
        );

        _addEntity(entity_);
        _versions[entity_] = version_;
    }

    /**
     * @inheritdoc IMigratablesRegistry
     */
    function migrate(address entity_, bytes memory data) external checkEntity(entity_) {
        if (msg.sender != MigratableEntity(entity_).owner()) {
            revert NotOwner();
        }

        uint256 currentVersion = _versions[entity_];
        uint256 newestVersion = _whitelistedImplementations.length();
        if (currentVersion == newestVersion) {
            revert AlreadyUpToDate();
        }

        _versions[entity_] = currentVersion + 1;

        UUPSUpgradeable(entity_).upgradeToAndCall(
            _whitelistedImplementations.at(currentVersion),
            abi.encodeWithSelector(MigratableEntity.migrate.selector, data)
        );
    }
}

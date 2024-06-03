// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMigratableEntity} from "src/interfaces/base/IMigratableEntity.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MigratableEntity is Initializable, OwnableUpgradeable, IMigratableEntity {
    /**
     * @inheritdoc IMigratableEntity
     */
    address public immutable FACTORY;

    modifier onlyFactory() {
        if (msg.sender != FACTORY) {
            revert NotFactory();
        }
        _;
    }

    constructor(address factory) {
        _disableInitializers();

        FACTORY = factory;
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
    function initialize(
        uint64 initialVersion,
        address owner_,
        bytes memory data
    ) external onlyFactory reinitializer(initialVersion) {
        __Ownable_init(owner_);

        _initialize(initialVersion, owner_, data);
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function migrate(uint64 newVersion, bytes memory data) external onlyFactory reinitializer(newVersion) {
        _migrate(newVersion, data);
    }

    function _initialize(uint64, address, bytes memory) internal virtual {}

    function _migrate(uint64, bytes memory) internal virtual {}
}

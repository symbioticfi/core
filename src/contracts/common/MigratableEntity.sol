// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

abstract contract MigratableEntity is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IMigratableEntity
{
    /**
     * @inheritdoc IMigratableEntity
     */
    address public immutable FACTORY;

    modifier notInitialized() {
        if (_getInitializedVersion() != 0) {
            revert AlreadyInitialized();
        }

        _;
    }

    constructor(
        address factory
    ) {
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
        bytes calldata data
    ) external notInitialized reinitializer(initialVersion) {
        __ReentrancyGuard_init();

        if (owner_ != address(0)) {
            __Ownable_init(owner_);
        }

        _initialize(initialVersion, owner_, data);
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function migrate(uint64 newVersion, bytes calldata data) external nonReentrant {
        if (msg.sender != FACTORY) {
            revert NotFactory();
        }

        _migrateInternal(_getInitializedVersion(), newVersion, data);
    }

    function _migrateInternal(
        uint64 oldVersion,
        uint64 newVersion,
        bytes calldata data
    ) private reinitializer(newVersion) {
        _migrate(oldVersion, newVersion, data);
    }

    function _initialize(uint64, /* initialVersion */ address, /* owner */ bytes memory /* data */ ) internal virtual {}

    function _migrate(uint64, /* oldVersion */ uint64, /* newVersion */ bytes calldata /* data */ ) internal virtual {}

    uint256[10] private __gap;
}

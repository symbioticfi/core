// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IMigratableEntity} from "src/interfaces/common/IMigratableEntity.sol";
import {IMigratablesFactory} from "src/interfaces/common/IMigratablesFactory.sol";

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

    address private immutable SELF;

    modifier uninitialized() {
        if (_getInitializedVersion() > 0) {
            revert AlreadyInitialized();
        }

        _;
    }

    constructor(
        address factory
    ) {
        _disableInitializers();

        FACTORY = factory;
        SELF = address(this);
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
    ) external uninitialized reinitializer(initialVersion) {
        if (SELF != IMigratablesFactory(FACTORY).implementation(initialVersion)) {
            revert InvalidInitialVersion();
        }

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

    function _initialize(uint64, address, bytes calldata) internal virtual {}

    function _migrate(uint64, uint64, bytes calldata) internal virtual {}
}

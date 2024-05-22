// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMigratableEntity} from "src/interfaces/IMigratableEntity.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MigratableEntity is Initializable, UUPSUpgradeable, OwnableUpgradeable, IMigratableEntity {
    // keccak256(abi.encode(uint256(keccak256("symbiotic.storage.MigratableEntity")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MigratableEntityStorageLocation =
        0x22b5f4baea4997f81f8aeb6360e0bdae13f074e0e55c27a8a6fab78cbad46200;

    modifier onlyRegistry() {
        if (msg.sender != registry()) {
            revert NotRegistry();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function registry() public view returns (address) {
        return _getMigratableEntityStorage()._registry;
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
        __UUPSUpgradeable_init();

        MigratableEntityStorage storage $ = _getMigratableEntityStorage();
        $._registry = msg.sender;
    }

    function _migrate() internal onlyRegistry {}

    function _authorizeUpgrade(address newImplementation) internal override onlyRegistry {}

    function _getMigratableEntityStorage() private pure returns (MigratableEntityStorage storage $) {
        assembly {
            $.slot := MigratableEntityStorageLocation
        }
    }
}

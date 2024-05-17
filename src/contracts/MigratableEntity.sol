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

    modifier onlyProxyAdmin() {
        if (msg.sender != proxyAdmin()) {
            revert NotProxyAdmin();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function proxyAdmin() public view returns (address) {
        return _getMigratableEntityStorage()._proxyAdmin;
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function initialize(bytes memory data) public virtual initializer {
        address owner = abi.decode(data, (address));
        __Ownable_init(owner);
        __UUPSUpgradeable_init();

        MigratableEntityStorage storage $ = _getMigratableEntityStorage();
        $._proxyAdmin = msg.sender;
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function migrate(bytes memory) public virtual onlyProxyAdmin reinitializer(_getInitializedVersion() + 1) {}

    function _authorizeUpgrade(address newImplementation) internal override onlyProxyAdmin {}

    function _getMigratableEntityStorage() private pure returns (MigratableEntityStorage storage $) {
        assembly {
            $.slot := MigratableEntityStorageLocation
        }
    }
}

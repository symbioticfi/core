// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMigratableEntityProxy} from "src/interfaces/IMigratableEntityProxy.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MigratableEntityProxy is TransparentUpgradeableProxy, IMigratableEntityProxy {
    constructor(
        address _logic,
        address initialOwner,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, initialOwner, _data) {}

    /**
     * @inheritdoc IMigratableEntityProxy
     */
    function proxyAdmin() external returns (address) {
        return _proxyAdmin();
    }
}

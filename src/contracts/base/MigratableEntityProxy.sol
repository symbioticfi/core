// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMigratableEntityProxy} from "src/interfaces/base/IMigratableEntityProxy.sol";

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MigratableEntityProxy is ERC1967Proxy, IMigratableEntityProxy {
    // An immutable address for the admin to avoid unnecessary SLOADs before each call.
    address private immutable _admin;

    /**
     * @dev The proxy caller is the current admin, and can't fallback to the proxy target.
     */
    error ProxyDeniedAdminAccess();

    /**
     * @dev Initializes an upgradeable proxy managed by `msg.sender`,
     * backed by the implementation at `_logic`, and optionally initialized with `_data` as explained in
     * {ERC1967Proxy-constructor}.
     */
    constructor(address _logic, bytes memory _data) payable ERC1967Proxy(_logic, _data) {
        _admin = msg.sender;
        // Set the storage value and emit an event for ERC-1967 compatibility
        ERC1967Utils.changeAdmin(_proxyAdmin());
    }

    /**
     * @inheritdoc IMigratableEntityProxy
     */
    function proxyAdmin() external view returns (address) {
        return _proxyAdmin();
    }

    /**
     * @inheritdoc IMigratableEntityProxy
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable {
        if (msg.sender != _proxyAdmin()) {
            revert ProxyDeniedAdminAccess();
        }

        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    /**
     * @dev Returns the admin of this proxy.
     */
    function _proxyAdmin() internal view returns (address) {
        return _admin;
    }
}

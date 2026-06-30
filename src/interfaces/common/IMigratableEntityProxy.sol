// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMigratableEntityProxy
 * @notice Interface for the MigratableEntityProxy contract.
 */
interface IMigratableEntityProxy {
    /**
     * @notice Upgrade the proxy to a new implementation and call a function on the new implementation.
     * @param newImplementation Address of the new implementation.
     * @param data Data to call on the new implementation.
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external;
}

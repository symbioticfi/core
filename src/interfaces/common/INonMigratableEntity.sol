// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface INonMigratableEntity {
    /**
     * @notice Initialize this entity contract using a given data.
     * @param data some data to use
     */
    function initialize(bytes memory data) external;
}

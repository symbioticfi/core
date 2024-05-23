// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IMigratableEntity {
    error NotProxyAdmin();

    /**
     * @notice Get a the entity's version.
     * @return version of the entity
     * @dev Starts from 1.
     */
    function version() external view returns (uint64);

    /**
     * @notice Initialize this entity contract using a given data.
     * @param version initial version of the entity
     * @param data some data to use
     */
    function initialize(uint64 version, bytes memory data) external;

    /**
     * @notice Migrate this entity to a newer version using a given data.
     * @param data some data to use
     */
    function migrate(bytes memory data) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IMigratableEntity {
    error NotProxyAdmin();

    struct MigratableEntityStorage {
        address _proxyAdmin;
    }

    /**
     * @notice Get the proxy admin address.
     * @return address of the proxy admin
     */
    function proxyAdmin() external view returns (address);

    /**
     * @notice Initialize this entity contract using a given data.
     * @param data some data to use
     */
    function initialize(bytes memory data) external;

    /**
     * @notice Migrate this entity to a newer version using a given data.
     * @param data some data to use
     */
    function migrate(bytes memory data) external;
}

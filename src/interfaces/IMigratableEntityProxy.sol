// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IMigratableEntityProxy {
    /**
     * @notice Get a proxy admin.
     * @return address of the proxy admin
     */
    function proxyAdmin() external returns (address);
}

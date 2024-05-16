// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IPlugin {
    error NotEntity();

    /**
     * @notice Get the registry address.
     * @return address of the registry
     */
    function REGISTRY() external view returns (address);
}

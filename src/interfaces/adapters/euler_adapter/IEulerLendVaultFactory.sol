// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEulerLendVaultFactory
 * @notice Minimal Euler EVK factory interface.
 */
interface IEulerLendVaultFactory {
    /* FUNCTIONS */

    /**
     * @notice Returns whether an address is a proxy deployed by the factory.
     * @param proxy Address to check.
     * @return status True if the address was deployed by this factory.
     */
    function isProxy(address proxy) external view returns (bool status);
}

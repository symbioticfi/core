// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IRewardsDistributorBase {
    error NotNetwork();

    /**
     * @notice Get the network registry's address.
     * @return address of the network registry
     * @dev Must be an immutable.
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the address of the vault.
     * @return address of the vault
     * @dev Must not change once set.
     */
    function VAULT() external view returns (address);

    /**
     * @notice Get a version of the rewards distributor (different versions mean different interfaces).
     * @return version of the rewards distributor
     * @dev May change for upgradable rewards distributors.
     */
    function version() external view returns (uint64);
}

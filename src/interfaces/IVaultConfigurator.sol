// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVaultConfigurator
 * @notice Interface for the VaultConfigurator contract.
 */
interface IVaultConfigurator {
    /**
     * @notice Initial parameters needed for a vault with a delegator and a slasher deployment.
     * @param version Entity's version to use.
     * @param owner Initial owner of the entity.
     * @param vaultParams Parameters for the vault initialization.
     * @param delegatorIndex Delegator's index of the implementation to deploy.
     * @param delegatorParams Parameters for the delegator initialization.
     * @param withSlasher Whether to deploy a slasher or not.
     * @param slasherIndex Slasher's index of the implementation to deploy (used only if withSlasher == true).
     * @param slasherParams Parameters for the slasher initialization (used only if withSlasher == true).
     */
    struct InitParams {
        uint64 version;
        address owner;
        bytes vaultParams;
        uint64 delegatorIndex;
        bytes delegatorParams;
        bool withSlasher;
        uint64 slasherIndex;
        bytes slasherParams;
    }

    /**
     * @notice Get the vault factory's address.
     * @return Address Of the vault factory.
     */
    function VAULT_FACTORY() external view returns (address);

    /**
     * @notice Get the delegator factory's address.
     * @return Address Of the delegator factory.
     */
    function DELEGATOR_FACTORY() external view returns (address);

    /**
     * @notice Get the slasher factory's address.
     * @return Address Of the slasher factory.
     */
    function SLASHER_FACTORY() external view returns (address);

    /**
     * @notice Create a new vault with a delegator and a slasher.
     * @param params Initial parameters needed for a vault with a delegator and a slasher deployment.
     * @return vault Address of the vault.
     * @return delegator Address of the delegator.
     * @return slasher Address of the slasher.
     */
    function create(InitParams calldata params) external returns (address vault, address delegator, address slasher);
}

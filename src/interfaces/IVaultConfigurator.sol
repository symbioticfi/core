// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IVault} from "src/interfaces/vault/IVault.sol";

interface IVaultConfigurator {
    error DirtyInitParams();

    /**
     * @notice Initial parameters needed for a vault with a delegator and a slashher deployment.
     * @param version entity's version to use
     * @param owner initial owner of the entity
     * @param vaultParams parameters for the vault initialization
     * @param delegatorIndex delegator's index of the implementation to deploy (used only if vaultParams.delegator == address(0))
     * @param delegatorParams parameters for the delegator initialization (used only if vaultParams.delegator == address(0))
     * @param withSlasher whether to deploy a slasher or not
     * @param slasherIndex slasher's index of the implementation to deploy (used only if vaultParams.slasher == address(0) and withSlasher == true)
     * @param slasherParams parameters for the slasher initialization (used only if vaultParams.slasher == address(0) and withSlasher == true)
     */
    struct InitParams {
        uint64 version;
        address owner;
        IVault.InitParams vaultParams;
        uint64 delegatorIndex;
        bytes delegatorParams;
        bool withSlasher;
        uint64 slasherIndex;
        bytes slasherParams;
    }

    /**
     * @notice Get the vault factory's address.
     * @return address of the vault factory
     */
    function VAULT_FACTORY() external view returns (address);

    /**
     * @notice Get the delegator factory's address.
     * @return address of the delegator factory
     */
    function DELEGATOR_FACTORY() external view returns (address);

    /**
     * @notice Get the slasher factory's address.
     * @return address of the slasher factory
     */
    function SLASHER_FACTORY() external view returns (address);

    /**
     * @notice Create a new vault with a delegator and a slasher.
     * @param params initial parameters needed for a vault with a delegator and a slasher deployment
     * @return vault address of the vault
     * @return delegator address of the delegator
     * @return slasher address of the slasher
     */
    function create(InitParams calldata params) external returns (address vault, address delegator, address slasher);
}

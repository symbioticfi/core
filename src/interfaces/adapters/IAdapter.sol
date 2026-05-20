// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratableEntity} from "../common/IMigratableEntity.sol";

/**
 * @title IAdapter
 * @notice Interface for the adapter contract.
 */
interface IAdapter is IMigratableEntity {
    /**
     * @notice Raised when the provided initialization vault is not registered.
     */
    error InvalidVault();

    /**
     * @notice Raised when the caller is not the adapter's vault or vault delegator.
     */
    error NotVault();

    /**
     * @notice Raised when the caller is not the curator for the target vault.
     */
    error NotCurator();

    /**
     * @notice Raised when allocation is attempted while skimmable yield remains unsettled.
     */
    error SkimFailed();

    /**
     * @notice Execute a batch of delegatecalls on the adapter.
     * @param data Calldata items to execute.
     */
    function multicall(bytes[] calldata data) external;

    /**
     * @notice Returns the vault served by the adapter.
     * @return vault Vault address.
     */
    function vault() external view returns (address vault);

    /**
     * @notice Get total assets managed by the adapter for a vault.
     * @return assets Total collateral-equivalent assets managed by the adapter.
     */
    function totalAssets() external view returns (uint256 assets);

    /**
     * @notice Get the current skimmable balance of the vault.
     * @return amount Amount of collateral that can be skimmed.
     */
    function skimmable() external view returns (uint256 amount);

    /**
     * @notice Get the amount of collateral that can be allocated to the adapter.
     * @return amount Amount of collateral that can be allocated to the adapter.
     */
    function allocatable() external view returns (uint256 amount);

    /**
     * @notice Get the amount of collateral that can be deallocated from the adapter instantly.
     * @return amount Amount of collateral that can be deallocated from the adapter.
     */
    function deallocatable() external view returns (uint256 amount);

    /**
     * @notice Allocate collateral to the adapter.
     * @param amount Amount of the collateral to allocate.
     * @dev Should not revert (except extreme cases to mitigate external manipulations).
     */
    function allocate(uint256 amount) external;

    /**
     * @notice Deallocate collateral from the adapter.
     * @param amount Amount of the collateral to deallocate.
     * @return deallocated Amount of the collateral deallocated now.
     * @return pending Amount of collateral accepted for delayed deallocation.
     * @dev Must not revert.
     */
    function deallocate(uint256 amount) external returns (uint256 deallocated, uint256 pending);

    /**
     * @notice Synchronize adapter pending deallocation accounting.
     */
    function sync() external;

    /**
     * @notice Skim the collateral from the adapter.
     * @return amount Amount of the collateral skimmed.
     * @dev Must not revert.
     */
    function skim() external returns (uint256 amount);
}

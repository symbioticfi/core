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
     * @notice Returns the vault served by the adapter.
     * @return vault Vault address.
     */
    function vault() external view returns (address vault);

    /**
     * @notice Execute a batch of delegatecalls on the adapter.
     * @param data Calldata items to execute.
     */
    function multicall(bytes[] calldata data) external;

    /**
     * @notice Get the amount of collateral that can be allocated to the adapter.
     * @return amount Amount of collateral that can be allocated to the adapter.
     */
    function allocatable() external view returns (uint256 amount);

    /**
     * @notice Get total assets managed by the adapter for a vault.
     * @return assets Total collateral-equivalent assets managed by the adapter.
     */
    function totalAssets() external view returns (uint256 assets);

    /**
     * @notice Get the amount of collateral that can be deallocated from the adapter instantly.
     * @return amount Amount of collateral that can be deallocated from the adapter.
     */
    function deallocatable() external view returns (uint256 amount);

    /**
     * @notice Allocate collateral to the adapter.
     * @param amount Amount of the collateral to allocate.
     * @return allocated Amount of the collateral allocated.
     * @dev Should not revert (except extreme cases to mitigate external manipulations).
     */
    function allocate(uint256 amount) external returns (uint256 allocated);

    /**
     * @notice Deallocate collateral from the adapter.
     * @param amount Amount of the collateral to deallocate.
     * @return deallocated Amount of the collateral deallocated now.
     * @dev Must not revert.
     */
    function deallocate(uint256 amount) external returns (uint256 deallocated);

    /**
     * @notice Request delayed deallocation from the adapter.
     * @param amount Amount of collateral requested for delayed deallocation.
     */
    function requestDeallocate(uint256 amount) external;
}

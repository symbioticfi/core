// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAdapterBase
 * @notice Interface for the AdapterBase contract.
 */
interface IAdapterBase {
    /**
     * @notice Get the amount of collateral that can be allocated to the adapter.
     * @param vault Address of the vault.
     * @return Amount Of collateral that can be allocated to the adapter.
     */
    function allocatable(address vault) external view returns (uint256);

    /**
     * @notice Get the amount of collateral that can be deallocated from the adapter instantly.
     * @return Amount Of collateral that can be deallocated from the adapter.
     */
    function deallocatable(address vault) external view returns (uint256);

    /**
     * @notice Allocate collateral to the adapter.
     * @param amount Amount of the collateral to allocate.
     * @dev Must not revert.
     */
    function allocate(uint256 amount) external;

    /**
     * @notice Deallocate collateral from the adapter instantly.
     * @param amount Amount of the collateral to deallocate.
     * @return Amount Of the collateral deallocated.
     * @dev Must not revert.
     */
    function deallocate(uint256 amount) external returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IPluginBase
 * @notice Interface for the PluginBase contract.
 */
interface IPluginBase {
    /**
     * @notice Get the current skimmable balance of the vault.
     * @param vault Address of the vault.
     */
    function skimmable(address vault) external view returns (uint256);

    /**
     * @notice Get the amount of collateral that can be allocated to the plugin.
     * @return Amount Of collateral that can be allocated to the plugin.
     */
    function allocatable() external view returns (uint256);

    /**
     * @notice Get the amount of collateral that can be deallocated from the plugin instantly.
     * @return Amount Of collateral that can be deallocated from the plugin.
     */
    function deallocatable(address vault) external view returns (uint256);

    /**
     * @notice Allocate collateral to the plugin.
     * @param amount Amount of the collateral to allocate.
     * @dev Must not revert.
     */
    function allocate(uint256 amount) external;

    /**
     * @notice Deallocate collateral from the plugin instantly.
     * @param amount Amount of the collateral to deallocate.
     * @return Amount Of the collateral deallocated.
     * @dev Must not revert.
     */
    function deallocate(uint256 amount) external returns (uint256);

    /**
     * @notice Skim the collateral from the plugin.
     * @param vault Address of the vault.
     * @return Amount Of the collateral skimmed.
     * @dev Must not revert.
     */
    function skim(address vault) external returns (uint256);
}

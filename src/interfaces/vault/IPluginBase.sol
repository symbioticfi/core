// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPluginBase {
    /**
     * @notice Get the current skimmable balance of the vault.
     * @param vault address of the vault
     */
    function skimmable(address vault) external view returns (uint256);

    /**
     * @notice Get the amount of collateral that can be allocated to the plugin.
     * @return amount of collateral that can be allocated to the plugin
     */
    function allocatable() external view returns (uint256);

    /**
     * @notice Get the amount of collateral that can be deallocated from the plugin instantly.
     * @return amount of collateral that can be deallocated from the plugin
     */
    function deallocatable(address vault) external view returns (uint256);

    /**
     * @notice Allocate collateral to the plugin.
     * @param amount amount of the collateral to allocate
     * @dev Must not revert.
     */
    function allocate(uint256 amount) external;

    /**
     * @notice Deallocate collateral from the plugin instantly.
     * @param amount amount of the collateral to deallocate
     * @return amount of the collateral deallocated
     * @dev Must not revert.
     */
    function deallocate(uint256 amount) external returns (uint256);

    /**
     * @notice Skim the collateral from the plugin.
     * @param vault address of the vault
     * @return amount of the collateral skimmed
     * @dev Must not revert.
     */
    function skim(address vault) external returns (uint256);
}

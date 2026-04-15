// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAdapter
 * @notice Interface for the adapter contract.
 */
interface IAdapter {
    /**
     * @notice Raised when the provided address is not a registered vault.
     */
    error NotVault();

    /**
     * @notice Raised when the caller is not the curator for the target vault.
     */
    error NotCurator();

    /**
     * @notice Raised when a zero amount is passed where a positive amount is required.
     */
    error ZeroAmount();

    /**
     * @notice Raised when allocation is attempted while skimmable yield remains unsettled.
     */
    error SkimFailed();

    /**
     * @notice Emitted when the global allocation limit is updated for an asset.
     * @param asset Asset address.
     * @param limit Adapter-wide allocation limit for the asset.
     */
    event SetGlobalLimit(address indexed asset, uint256 limit);

    /**
     * @notice Emitted when curator-provided recovery collateral is returned to a vault.
     * @param vault Vault address.
     * @param amount Recovered collateral amount.
     */
    event Recover(address indexed vault, uint256 amount);

    /**
     * @notice Execute a batch of delegatecalls on the adapter.
     * @param data Calldata items to execute.
     */
    function multicall(bytes[] calldata data) external;

    /**
     * @notice Returns the adapter-wide allocation limit for an asset.
     * @param asset Asset address.
     * @return limit Allocation limit for the asset.
     */
    function globalLimit(address asset) external view returns (uint256 limit);

    /**
     * @notice Sets the adapter-wide allocation limit for an asset.
     * @param asset Asset address.
     * @param limit Allocation limit for the asset.
     */
    function setGlobalLimit(address asset, uint256 limit) external;

    /**
     * @notice Get the current skimmable balance of the vault.
     * @param vault Address of the vault.
     * @return amount Amount of collateral that can be skimmed.
     */
    function skimmable(address vault) external view returns (uint256 amount);

    /**
     * @notice Get the amount of collateral that can be allocated to the adapter.
     * @param vault Address of the vault.
     * @return amount Amount of collateral that can be allocated to the adapter.
     */
    function allocatable(address vault) external view returns (uint256 amount);

    /**
     * @notice Get the amount of collateral that can be deallocated from the adapter instantly.
     * @param vault Address of the vault.
     * @return amount Amount of collateral that can be deallocated from the adapter.
     */
    function deallocatable(address vault) external view returns (uint256 amount);

    /**
     * @notice Allocate collateral to the adapter.
     * @param amount Amount of the collateral to allocate.
     * @dev Must not revert.
     */
    function allocate(uint256 amount) external;

    /**
     * @notice Deallocate collateral from the adapter instantly.
     * @param amount Amount of the collateral to deallocate.
     * @return deallocated Amount of the collateral deallocated.
     * @dev Must not revert.
     */
    function deallocate(uint256 amount) external returns (uint256 deallocated);

    /**
     * @notice Skim the collateral from the adapter.
     * @param vault Address of the vault.
     * @return amount Amount of the collateral skimmed.
     * @dev Must not revert.
     */
    function skim(address vault) external returns (uint256 amount);

    /**
     * @notice Replenish lost collateral and immediately return it to the vault.
     * @param vault Address of the vault.
     * @param amount Amount of collateral supplied for recovery.
     */
    function recover(address vault, uint256 amount) external;
}

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
     * @notice Raised when a zero amount is passed where a positive amount is required.
     */
    error ZeroAmount();

    /**
     * @notice Raised when allocation is attempted while skimmable yield remains unsettled.
     */
    error SkimFailed();

    /**
     * @notice Emitted when curator-provided recovery collateral is returned to a vault.
     * @param amount Recovered collateral amount.
     */
    event Recover(uint256 amount);

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
     * @notice Deallocate collateral from the adapter instantly.
     * @param amount Amount of the collateral to deallocate.
     * @return deallocated Amount of the collateral deallocated.
     * @dev Must not revert.
     */
    function deallocate(uint256 amount) external returns (uint256 deallocated);

    /**
     * @notice Skim the collateral from the adapter.
     * @return amount Amount of the collateral skimmed.
     * @dev Must not revert.
     */
    function skim() external returns (uint256 amount);

    /**
     * @notice Replenish lost collateral and immediately return it to the vault.
     * @param amount Amount of collateral supplied for recovery.
     */
    function recover(uint256 amount) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratableEntity} from "../common/IMigratableEntity.sol";
import {IMulticallable} from "../common/IMulticallable.sol";

/**
 * @title IAdapter
 * @notice Interface for the adapter contract.
 */
interface IAdapter is IMigratableEntity, IMulticallable {
    /* ERRORS */

    /**
     * @notice Raised when the provided initialization vault is not registered.
     */
    error InvalidVault();

    /**
     * @notice Raised when the caller is not the curator for the target vault.
     */
    error NotCurator();

    /**
     * @notice Raised when the caller is not the adapter's vault or vault delegator.
     */
    error NotVault();

    /* EVENTS */

    /**
     * @notice Emitted when the adapter vault is set.
     * @param vault Vault address.
     */
    event SetVault(address indexed vault);

    /* FUNCTIONS */

    /**
     * @notice Returns the vault served by the adapter.
     * @return vault Vault address.
     */
    function vault() external view returns (address vault);

    /**
     * @notice Get the amount of assets that can be allocated to the adapter.
     * @return amount Amount of assets that can be allocated to the adapter.
     */
    function allocatable() external view returns (uint256 amount);

    /**
     * @notice Get total assets managed by the adapter for a vault.
     * @return assets Total assets managed by the adapter.
     */
    function totalAssets() external view returns (uint256 assets);

    /**
     * @notice Get free assets held directly by the adapter.
     * @return assets Free assets held directly by the adapter.
     */
    function freeAssets() external view returns (uint256 assets);

    /**
     * @notice Allocate assets to the adapter.
     * @param amount Amount of assets to allocate.
     * @return allocated Amount of assets allocated.
     * @dev Should not revert (except extreme cases to mitigate external manipulations).
     */
    function allocate(uint256 amount) external returns (uint256 allocated);

    /**
     * @notice Deallocate assets from the adapter.
     * @param amount Amount of assets to deallocate.
     * @return deallocated Amount of assets deallocated now.
     * @dev Must not revert.
     */
    function deallocate(uint256 amount) external returns (uint256 deallocated);

    /**
     * @notice Request delayed deallocation from the adapter.
     * @param amount Amount of assets requested for delayed deallocation.
     */
    function requestDeallocate(uint256 amount) external;
}

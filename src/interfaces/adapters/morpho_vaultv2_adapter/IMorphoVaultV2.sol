// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IMorphoVaultV2
 * @notice Minimal Morpho Vault V2 interface used by the adapter.
 */
interface IMorphoVaultV2 is IERC4626 {
    /**
     * @notice Returns the configured adapter registry.
     * @return adapterRegistryAddress Adapter registry address.
     */
    function adapterRegistry() external view returns (address adapterRegistryAddress);

    /**
     * @notice Returns the configured liquidity adapter.
     * @return liquidityAdapterAddress Liquidity adapter address.
     */
    function liquidityAdapter() external view returns (address liquidityAdapterAddress);

    /**
     * @notice Returns whether the selector has been abdicated.
     * @param selector The selector to query.
     * @return status Whether the selector has been abdicated.
     */
    function abdicated(bytes4 selector) external view returns (bool status);

    /**
     * @notice Selector setter referenced by the adapter's vault validation.
     * @param newAdapterRegistry The new adapter registry.
     */
    function setAdapterRegistry(address newAdapterRegistry) external;
}

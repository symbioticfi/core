// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMorphoVaultV2Factory
 * @notice Minimal Morpho Vault V2 factory interface used by the adapter.
 */
interface IMorphoVaultV2Factory {
    /**
     * @notice Returns whether an address is a Morpho Vault V2.
     * @param vault The vault address to query.
     * @return status Whether the address is a Morpho Vault V2.
     */
    function isVaultV2(address vault) external view returns (bool status);
}

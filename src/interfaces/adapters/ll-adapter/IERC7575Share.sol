// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IERC7575Share
 * @notice Minimal ERC-7575 share-token interface used to resolve asset-specific vaults.
 */
interface IERC7575Share {
    /* FUNCTIONS */

    /**
     * @notice Returns the vault for an asset.
     * @param asset The asset address.
     * @return vault The ERC-7575 vault address.
     */
    function vault(address asset) external view returns (address vault);
}

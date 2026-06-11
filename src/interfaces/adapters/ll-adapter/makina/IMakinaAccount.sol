// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/**
 * @title IMakinaAccount
 * @notice Interface for Makina liquidity lane accounts.
 */
interface IMakinaAccount is ICooldownAccount {
    /* ERRORS */

    /**
     * @notice Raised when the Makina accounting token is not the vault asset.
     */
    error InvalidAsset();

    /* FUNCTIONS */

    /**
     * @notice Returns the Makina async redeemer.
     * @return redeemer The async redeemer address.
     */
    function REDEEMER() external view returns (address redeemer);

    /**
     * @notice Returns a Makina redemption receipt id by index.
     * @param index The request index.
     * @return requestId The redemption receipt id.
     */
    function requestIds(uint256 index) external view returns (uint64 requestId);

    /**
     * @notice Returns the request-time vault-asset quote capping a pending request's value.
     * @param requestId The redemption receipt id.
     * @return assets The quoted vault-asset value (0 for requests created before quoting).
     */
    function requestQuotes(uint64 requestId) external view returns (uint256 assets);

    /**
     * @notice Accepts Makina redemption receipt NFTs.
     * @return selector The ERC721 receiver selector.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4 selector);
}

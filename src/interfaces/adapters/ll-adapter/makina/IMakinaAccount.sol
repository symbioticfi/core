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
}

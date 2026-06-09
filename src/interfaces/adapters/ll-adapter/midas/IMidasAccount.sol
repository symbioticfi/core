// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/// @dev Midas redemption-request status for a pending (not yet processed) request.
uint8 constant REQUEST_STATUS_PENDING = 0;

/**
 * @title IMidasAccount
 * @notice Interface for Midas liquidity lane accounts.
 */
interface IMidasAccount is ICooldownAccount {
    /* ERRORS */

    /**
     * @notice Raised when the account vault asset is invalid for the configured Midas redemption token.
     */
    error InvalidAsset();

    /* FUNCTIONS */

    /**
     * @notice Returns the fallback redemption token when the vault asset is not configured in Midas.
     * @return redemptionToken The fallback redemption token.
     */
    function REDEMPTION_TOKEN() external view returns (address redemptionToken);

    /**
     * @notice Returns the Midas redemption vault.
     * @return redemptionVault The Midas redemption vault.
     */
    function REDEMPTION_VAULT() external view returns (address redemptionVault);

    /**
     * @notice Returns a Midas redemption request id by index.
     * @param index The request index.
     * @return requestId The redemption request id.
     */
    function requestIds(uint256 index) external view returns (uint64 requestId);
}

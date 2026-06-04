// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "../IAccount.sol";

/// @dev Midas redemption-request status for a pending (not yet processed) request.
uint8 constant REQUEST_STATUS_PENDING = 0;

/**
 * @title IMidasAccount
 * @notice Interface for Midas liquidity lane accounts.
 */
interface IMidasAccount is IAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the minimum delay between redemption requests.
     * @return cooldown The cooldown duration.
     */
    function COOLDOWN() external view returns (uint48 cooldown);

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
     * @notice Returns the timestamp of the latest redemption request.
     * @return time The latest redemption request timestamp.
     */
    function lastRequestTimestamp() external view returns (uint48 time);
}

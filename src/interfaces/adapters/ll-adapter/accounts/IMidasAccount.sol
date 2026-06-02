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
     * @notice Returns the adapter bound to the account.
     * @return adapter The adapter address.
     */
    function adapter() external view returns (address adapter);

    /**
     * @notice Returns the token submitted to Midas for redemption.
     * @return tokenToRedeem The token-to-redeem address.
     */
    function TOKEN_TO_REDEEM() external view returns (address tokenToRedeem);

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
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAsyncRedeemAccount
 * @notice Interface for liquidity lane accounts that redeem through ERC-7540 async redeem vaults.
 */
interface IAsyncRedeemAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the minimum delay between redemption requests for non-owner callers.
     * @return cooldown The cooldown duration.
     */
    function COOLDOWN() external view returns (uint48 cooldown);

    /**
     * @notice Returns the ERC-7540 async redeem vault.
     * @return vault The async redeem vault address.
     */
    function ASYNC_REDEEM_VAULT() external view returns (address vault);

    /**
     * @notice Returns the timestamp of the latest redemption request.
     * @return time The latest redemption request timestamp.
     */
    function lastRequestTimestamp() external view returns (uint48 time);
}

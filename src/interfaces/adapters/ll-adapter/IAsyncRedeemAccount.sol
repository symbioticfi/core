// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAsyncRedeemAccount
 * @notice Interface for liquidity lane accounts that redeem through ERC-7540 async redeem vaults.
 */
interface IAsyncRedeemAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the ERC-7540 async redeem vault.
     * @return vault The async redeem vault address.
     */
    function ASYNC_REDEEM_VAULT() external view returns (address vault);

    /**
     * @notice Returns the share token submitted to the async redeem vault.
     * @return share The redeem share token address.
     */
    function REDEEM_SHARE() external view returns (address share);
}

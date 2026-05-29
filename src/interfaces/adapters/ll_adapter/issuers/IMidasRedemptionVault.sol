// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMidasRedemptionVault
 * @notice Interface for Midas standard redemption vaults.
 */
interface IMidasRedemptionVault {
    /* FUNCTIONS */

    /**
     * @notice Returns the payment-token config for a token.
     * @param token The token address.
     * @return dataFeed The token data-feed address.
     * @return fee The token fee.
     * @return allowance The remaining allowance.
     * @return stable Whether the token is marked as stable.
     */
    function tokensConfig(address token)
        external
        view
        returns (address dataFeed, uint256 fee, uint256 allowance, bool stable);

    /**
     * @notice Requests redemption into the target output token.
     * @param tokenOut The token to receive from the redemption request.
     * @param amountMTokenIn The token amount to redeem.
     */
    function redeemRequest(address tokenOut, uint256 amountMTokenIn) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMidasDataFeed} from "../oracles/IMidasOracle.sol";

/**
 * @title IMidasRedemptionVault
 * @notice Interface for Midas standard redemption vaults.
 */
interface IMidasRedemptionVault {
    /* FUNCTIONS */

    /**
     * @notice Returns the Midas token data feed.
     * @return dataFeed The Midas token data feed.
     */
    function mTokenDataFeed() external view returns (IMidasDataFeed dataFeed);

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
     * @return requestId The created redemption request id.
     */
    function redeemRequest(address tokenOut, uint256 amountMTokenIn) external returns (uint256 requestId);

    /**
     * @notice Returns a standard redemption request.
     * @param requestId The redemption request id.
     * @return sender The request creator.
     * @return tokenOut The requested output token.
     * @return status The request status.
     * @return amountMToken The net token-to-redeem amount in the request.
     * @return mTokenRate The token-to-redeem rate recorded on the request.
     * @return tokenOutRate The output-token rate recorded on the request.
     */
    function redeemRequests(uint256 requestId)
        external
        view
        returns (
            address sender,
            address tokenOut,
            uint8 status,
            uint256 amountMToken,
            uint256 mTokenRate,
            uint256 tokenOutRate
        );
}

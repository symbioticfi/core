// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAccountRegistry
 * @notice Interface for the liquidity lane account registry.
 */
interface IAccountRegistry {
    /* ERRORS */

    /**
     * @notice Raised when a registry configuration is invalid.
     */
    error InvalidConfiguration();

    /* EVENTS */

    /**
     * @notice Emitted when a token-to-redeem account factory is updated.
     * @param tokenToRedeem The token-to-redeem address.
     * @param factory The account factory address.
     */
    event SetAccountFactory(address indexed tokenToRedeem, address indexed factory);

    /* FUNCTIONS */

    /**
     * @notice Returns the account factory for a token-to-redeem.
     * @param tokenToRedeem The token-to-redeem address.
     * @return factory The account factory address.
     */
    function accountFactories(address tokenToRedeem) external view returns (address factory);

    /**
     * @notice Sets the account factory for a token-to-redeem.
     * @param tokenToRedeem The token-to-redeem address.
     * @param factory The account factory address.
     */
    function setAccountFactory(address tokenToRedeem, address factory) external;
}

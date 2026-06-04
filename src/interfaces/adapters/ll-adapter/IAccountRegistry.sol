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

    /**
     * @notice Raised when an account factory is already configured.
     */
    error AccountFactoryAlreadySet();

    /* EVENTS */

    /**
     * @notice Emitted when an asset-specific token-to-redeem account factory is set.
     * @param asset The vault asset address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param factory The account factory address.
     */
    event SetAccountFactory(address indexed asset, address indexed tokenToRedeem, address indexed factory);

    /* FUNCTIONS */

    /**
     * @notice Returns the account factory for an asset and token-to-redeem pair.
     * @param asset The vault asset address.
     * @param tokenToRedeem The token-to-redeem address.
     * @return factory The account factory address.
     */
    function accountFactories(address asset, address tokenToRedeem) external view returns (address factory);

    /**
     * @notice Sets the account factory for an asset and token-to-redeem pair.
     * @param asset The vault asset address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param factory The account factory address.
     */
    function setAccountFactory(address asset, address tokenToRedeem, address factory) external;
}

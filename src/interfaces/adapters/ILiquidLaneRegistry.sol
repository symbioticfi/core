// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratablesFactory} from "../common/IMigratablesFactory.sol";

/**
 * @title ILiquidLaneRegistry
 * @notice Interface for the liquidity lane adapter registry.
 */
interface ILiquidLaneRegistry is IMigratablesFactory {
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

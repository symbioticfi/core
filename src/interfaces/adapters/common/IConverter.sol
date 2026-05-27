// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IConverter
 * @notice Interface for token conversion logic.
 */
interface IConverter {
    /* FUNCTIONS */

    /**
     * @notice Converts one token into another.
     * @param tokenIn Input token address.
     * @param tokenOut Output token address.
     * @param amountIn Input token amount.
     * @param minAmountOut Minimum output token amount.
     * @param data Converter-specific route data.
     */
    function convert(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes calldata data)
        external;
}

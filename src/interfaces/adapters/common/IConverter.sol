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
     * @param amountIn Input token amount.
     * @param data Converter-specific route data.
     */
    function convert(address tokenIn, uint256 amountIn, bytes calldata data) external;
}

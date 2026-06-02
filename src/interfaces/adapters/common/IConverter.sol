// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IConverter
 * @notice Interface for token conversion logic.
 */
interface IConverter {
    /* ERRORS */

    /**
     * @notice Raised when the output token is invalid.
     */
    error InvalidTokenOut();

    /* FUNCTIONS */

    /**
     * @notice Returns the converters allowed to create conversion orders without the prepared-request delay.
     * @return converters The authorized converter addresses.
     */
    function converters() external view returns (address[] memory converters);

    /**
     * @notice Converts one token into another.
     * @param tokenIn Input token address.
     * @param amountIn Input token amount.
     * @param tokenOut Output token address.
     * @param data Converter-specific route data.
     */
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data) external;
}

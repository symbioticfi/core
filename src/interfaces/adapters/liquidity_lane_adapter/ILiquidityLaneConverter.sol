// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILiquidityLaneConverter
 * @notice Interface for conversion logic delegatecalled by liquidity lane accounts.
 */
interface ILiquidityLaneConverter {
    /* FUNCTIONS */

    /**
     * @notice Converts one token into another.
     * @param tokenIn Input token.
     * @param tokenOut Output token.
     * @param amountIn Input amount.
     * @param minAmountOut Minimum output amount.
     * @param data Converter-specific data.
     * @dev Called through `delegatecall`; `address(this)` is the account holding `amountIn`.
     */
    function convert(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes calldata data)
        external;
}

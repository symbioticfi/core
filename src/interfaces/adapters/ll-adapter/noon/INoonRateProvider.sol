// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title INoonRateProvider
 * @notice Interface for Noon token quote providers.
 */
interface INoonRateProvider {
    /* FUNCTIONS */

    /**
     * @notice Quotes a base-token amount in quote-token units.
     * @param baseAmount The base-token amount.
     * @param baseToken The base token.
     * @param quoteToken The quote token.
     * @return quoteAmount The equivalent quote-token amount.
     */
    function getQuote(uint256 baseAmount, address baseToken, address quoteToken)
        external
        view
        returns (uint256 quoteAmount);
}

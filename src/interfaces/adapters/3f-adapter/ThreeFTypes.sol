// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Precision used for request yield values expressed in ppm.
uint256 constant YIELD_PRECISION = 10 ** 6;

/**
 * @notice 3F bridge facilitator offer.
 * @param maker Maker address.
 * @param amount Principal amount.
 * @param expectedReturn Expected yield amount.
 * @param nonce Offer nonce.
 * @param expiration Offer expiration timestamp.
 * @param useCallback Whether the request calls the maker callback.
 */
struct Offer {
    address maker;
    uint256 amount;
    uint256 expectedReturn;
    uint256 nonce;
    uint256 expiration;
    bool useCallback;
}

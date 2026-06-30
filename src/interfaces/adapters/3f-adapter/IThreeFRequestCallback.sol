// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Offer} from "./ThreeFTypes.sol";

/**
 * @title IThreeFRequestCallback
 * @notice Interface for 3F request consumption callbacks.
 */
interface IThreeFRequestCallback {
    /**
     * @notice Called by a request before it pulls principal from a maker.
     * @param offer Offer being consumed.
     * @param signature Offer signature.
     * @param principal Principal amount pulled after the callback.
     * @param yieldAmount Yield token amount minted by the request.
     */
    function onRequestConsumed(Offer calldata offer, bytes calldata signature, uint256 principal, uint256 yieldAmount)
        external;
}

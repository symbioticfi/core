// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";
import {IThreeFRequestCallback} from "./3f-adapter/IThreeFRequestCallback.sol";
import {Offer} from "./3f-adapter/ThreeFTypes.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @dev Maximum active 3F requests tracked by one adapter.
uint256 constant MAX_REQUESTS = 50;

/**
 * @title IThreeFAdapter
 * @notice Interface for the 3F bridge facilitator adapter.
 */
interface IThreeFAdapter is IAdapter, IThreeFRequestCallback, IERC1271 {
    /* ERRORS */

    /// @notice Raised when a request cannot be fully funded through the delegator.
    error InsufficientAllocate();

    /// @notice Raised when the request already has an active position.
    error AlreadyRequest();

    /// @notice Raised when the callback caller is not an active whitelisted 3F request.
    error NotRequest();

    /// @notice Raised when the request principal exceeds the configured per-request maximum.
    error TooLargeRequest();

    /// @notice Raised when the adapter already tracks the maximum number of active requests.
    error TooManyRequests();

    /// @notice Raised when the request yield is below the configured minimum.
    error TooLowYield();

    /// @notice Raised when the request principal is below the configured per-request minimum.
    error TooSmallRequest();

    /// @notice Raised when a 3F request asset differs from the vault asset.
    error WrongAsset();

    /* EVENTS */

    /**
     * @notice Emitted when the offer signer is set.
     * @param offerSigner Offer signer.
     */
    event SetOfferSigner(address indexed offerSigner);

    /**
     * @notice Emitted when per-request limits are set.
     * @param minYieldPerRequest Minimum request yield in ppm.
     * @param minAssetsPerRequest Minimum principal assets per request.
     * @param maxAssetsPerRequest Maximum principal assets per request.
     */
    event SetLimitsPerRequest(uint256 minYieldPerRequest, uint256 minAssetsPerRequest, uint256 maxAssetsPerRequest);

    /**
     * @notice Emitted when a 3F request is consumed by this adapter.
     * @param request Request address.
     * @param offer Consumed 3F offer payload.
     * @param principalAssets Principal assets funded into the request.
     * @param yieldAssets Yield assets minted by the request.
     */
    event OnRequestConsumed(address indexed request, Offer offer, uint256 principalAssets, uint256 yieldAssets);

    /**
     * @notice Emitted when a withdrawable 3F request is finalized into adapter-held assets.
     * @param request Request address.
     */
    event FinalizeRequest(address indexed request);

    /* FUNCTIONS */

    /**
     * @notice Returns the request whitelist.
     * @return requestWhitelist Request whitelist.
     */
    function REQUEST_WHITELIST() external view returns (address requestWhitelist);

    /**
     * @notice Returns the minimum request yield in ppm.
     * @return ppm Minimum request yield in ppm.
     */
    function minYieldPerRequest() external view returns (uint256 ppm);

    /**
     * @notice Returns the minimum principal assets accepted per request.
     * @return assets Minimum principal assets per request.
     */
    function minAssetsPerRequest() external view returns (uint256 assets);

    /**
     * @notice Returns the maximum principal assets accepted per request.
     * @return assets Maximum principal assets per request.
     */
    function maxAssetsPerRequest() external view returns (uint256 assets);

    /**
     * @notice Returns the signer accepted by EIP-1271 offer validation.
     * @return signer Offer signer.
     */
    function offerSigner() external view returns (address signer);

    /**
     * @notice Returns an active request by index.
     * @param index Request index.
     * @return request Request address.
     */
    function requests(uint256 index) external view returns (address request);

    /**
     * @notice Returns the one-based active request index, or zero if inactive.
     * @param request Request address.
     * @return index One-based active request index.
     */
    function requestIndex(address request) external view returns (uint256 index);

    /**
     * @notice Returns the maximum principal assets that can currently be funded into a new request.
     * @return assets Maximum assets available for the next request.
     */
    function getMaxAssets() external returns (uint256 assets);

    /**
     * @notice Sets the signer accepted by EIP-1271 offer validation.
     * @param signer Offer signer.
     */
    function setOfferSigner(address signer) external;

    /**
     * @notice Sets per-request principal and yield limits.
     * @param newMinYieldPerRequest Minimum request yield in ppm.
     * @param newMinAssetsPerRequest Minimum principal assets per request.
     * @param newMaxAssetsPerRequest Maximum principal assets per request.
     */
    function setLimitsPerRequest(
        uint256 newMinYieldPerRequest,
        uint256 newMinAssetsPerRequest,
        uint256 newMaxAssetsPerRequest
    ) external;

    /**
     * @notice Finalizes a withdrawable request into adapter-held assets.
     * @param request Request address.
     */
    function finalizeRequest(address request) external;
}

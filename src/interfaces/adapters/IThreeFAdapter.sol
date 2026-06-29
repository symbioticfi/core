// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

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

/**
 * @title IThreeFRequest
 * @notice Minimal interface for 3F requests.
 */
interface IThreeFRequest {
    /**
     * @notice Returns the request asset.
     * @return asset Request asset.
     */
    function asset() external view returns (address asset);
}

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

/**
 * @title IThreeFVaultController
 * @notice Minimal interface for 3F request vault redemption.
 */
interface IThreeFVaultController {
    /**
     * @notice Returns whether redemption is available.
     * @return status Whether redemption is available.
     */
    function canWithdraw() external view returns (bool status);

    /**
     * @notice Burns all principal and yield shares owned by an account.
     * @param owner Account whose shares are burned.
     * @param receiver Asset receiver.
     * @return ptShares Burned principal token shares.
     * @return ytShares Burned yield token shares.
     * @return pAssets Redeemed principal assets.
     * @return yAssets Redeemed yield assets.
     */
    function burnAll(address owner, address receiver)
        external
        returns (uint256 ptShares, uint256 ytShares, uint256 pAssets, uint256 yAssets);
}

/**
 * @title IThreeFWhitelist
 * @notice Minimal 3F request whitelist interface.
 */
interface IThreeFWhitelist {
    /**
     * @notice Request whitelist status.
     */
    enum WhitelistStatus {
        NotWhitelisted,
        Whitelisted,
        PausedNotWhitelisted,
        PausedWhitelisted
    }

    /**
     * @notice Returns request whitelist status.
     * @param account Account to query.
     * @return status Whitelist status.
     */
    function isWhitelisted(address account) external view returns (WhitelistStatus status);
}

/**
 * @title IThreeFAdapter
 * @notice Interface for the 3F bridge facilitator adapter.
 */
interface IThreeFAdapter is IAdapter, IThreeFRequestCallback, IERC1271 {
    /* ERRORS */

    /**
     * @notice Raised when a 3F request asset differs from the vault asset.
     */
    error AssetMismatch();

    /**
     * @notice Raised when the just-in-time allocation cannot fully fund the request.
     */
    error InsufficientLiquidity();

    /**
     * @notice Raised when the request is not currently whitelisted.
     */
    error NotAttested();

    /**
     * @notice Raised when the request exceeds the configured per-request cap.
     */
    error PerRequestCapExceeded();

    /**
     * @notice Raised when the request would exceed the configured loan cap.
     */
    error TooManyLoans();

    /**
     * @notice Raised when the request yield is below the configured floor.
     */
    error YieldTooLow();

    /* STRUCTS */

    /**
     * @notice Opened 3F position.
     * @param principal Principal funded into the request.
     * @param ytExpected Offer-time expected yield.
     * @param openedAt Timestamp when the position was opened.
     * @param redeemed Whether the position has been redeemed.
     */
    struct Position {
        uint256 principal;
        uint256 ytExpected;
        uint48 openedAt;
        bool redeemed;
    }

    /* EVENTS */

    /**
     * @notice Emitted when the offer signer is set.
     * @param signer Offer signer.
     */
    event SetOfferSigner(address indexed signer);

    /**
     * @notice Emitted when exposure limits are set.
     * @param perRequestMaxCollateral Maximum principal per request.
     * @param minRequestYield Minimum request yield in ppm.
     * @param maxConcurrentLoans Maximum number of concurrent open loans (0 = no limit).
     */
    event SetExposureLimits(uint256 perRequestMaxCollateral, uint256 minRequestYield, uint256 maxConcurrentLoans);

    /**
     * @notice Emitted when a request position is opened.
     * @param request Request address.
     * @param principal Principal funded into the request.
     * @param ytExpected Offer-time expected yield.
     */
    event PositionOpened(address indexed request, uint256 principal, uint256 ytExpected);

    /**
     * @notice Emitted when a request position is redeemed.
     * @param request Request address.
     * @param principal Redeemed principal assets.
     * @param yieldAmount Redeemed yield assets.
     */
    event PositionRedeemed(address indexed request, uint256 principal, uint256 yieldAmount);

    /* FUNCTIONS */

    /**
     * @notice Returns the request whitelist.
     * @return requestWhitelist Request whitelist.
     */
    function REQUEST_WHITELIST() external view returns (address requestWhitelist);

    /**
     * @notice Returns the maximum number of concurrent open loans (0 = no limit).
     * @return count Maximum concurrent open loans.
     */
    function maxConcurrentLoans() external view returns (uint256 count);

    /**
     * @notice Returns the signer accepted by EIP-1271 offer validation.
     * @return signer Offer signer.
     */
    function offerSigner() external view returns (address signer);

    /**
     * @notice Returns a request position.
     * @param request Request address.
     * @return principal Principal funded into the request.
     * @return ytExpected Offer-time expected yield.
     * @return openedAt Timestamp when the position was opened.
     * @return redeemed Whether the position has been redeemed.
     */
    function positions(address request)
        external
        view
        returns (uint256 principal, uint256 ytExpected, uint48 openedAt, bool redeemed);

    /**
     * @notice Returns whether a request is currently open.
     * @param request Request address.
     * @return status Whether the request is currently open.
     */
    function isRequest(address request) external view returns (bool status);

    /**
     * @notice Returns the number of currently open requests.
     * @return count Open request count.
     */
    function activeLoans() external view returns (uint256 count);

    /**
     * @notice Returns the currently open (consumed, unredeemed) requests.
     * @return requests The open request addresses.
     */
    function activeRequests() external view returns (address[] memory requests);

    /**
     * @notice Returns realized principal not yet recalled by the vault.
     * @return assets Realized principal assets.
     */
    function realizedPrincipal() external view returns (uint256 assets);

    /**
     * @notice Returns principal currently locked in open 3F requests.
     * @return assets Outstanding principal assets.
     */
    function outstandingPrincipal() external view returns (uint256 assets);

    /**
     * @notice Returns the maximum principal per request.
     * @return assets Maximum principal per request.
     */
    function perRequestMaxCollateral() external view returns (uint256 assets);

    /**
     * @notice Returns the minimum request yield in ppm.
     * @return ppm Minimum request yield in ppm.
     */
    function minRequestYield() external view returns (uint256 ppm);

    /**
     * @notice Sets the signer accepted by EIP-1271 offer validation.
     * @param signer Offer signer.
     */
    function setOfferSigner(address signer) external;

    /**
     * @notice Sets adapter-level exposure limits.
     * @param perRequestMaxCollateral_ Maximum principal per request.
     * @param minRequestYield_ Minimum request yield in ppm.
     * @param maxConcurrentLoans_ Maximum number of concurrent open loans (0 = no limit).
     */
    function setExposureLimits(uint256 perRequestMaxCollateral_, uint256 minRequestYield_, uint256 maxConcurrentLoans_)
        external;

    /**
     * @notice Redeems ready 3F requests.
     * @param requests Requests to redeem.
     */
    function redeem(address[] calldata requests) external;
}

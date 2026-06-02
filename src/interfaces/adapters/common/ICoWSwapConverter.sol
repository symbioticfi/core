// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConverter} from "./IConverter.sol";

/// @dev CoW Protocol "sell" order kind.
bytes32 constant COW_SWAP_KIND_SELL = hex"f3b277728b3fee749481eb3e0b3b48980dbbab78658fc419025cb16eee346775";

/// @dev CoW Protocol ERC20 balance marker.
bytes32 constant COW_SWAP_BALANCE_ERC20 = hex"5a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9";

/// @dev CoW Protocol order typehash.
bytes32 constant COW_SWAP_ORDER_TYPEHASH = hex"d5a25ba2e97094ad7d83dc28a6572da797d6b3e7fc6663bd93efb789fc17e489";

/// @dev Encoded CoW Protocol order UID length.
uint256 constant COW_SWAP_ORDER_UID_LENGTH = 56;

/// @dev Delay before a prepared conversion can be executed permissionlessly.
uint256 constant EXECUTION_DELAY = 1 days;

/// @dev Maximum distance allowed between `block.timestamp` and CoW order `validTo`.
uint32 constant MAX_VALID_TO_DURATION = 30 minutes;

/**
 * @title ICoWSwapSettlement
 * @notice Interface for the CoW Protocol settlement contract.
 */
interface ICoWSwapSettlement {
    /* FUNCTIONS */

    /**
     * @notice Sets or clears the pre-signature for an order UID.
     * @param orderUid The order UID.
     * @param signed The new pre-signature status.
     */
    function setPreSignature(bytes calldata orderUid, bool signed) external;

    /**
     * @notice Returns the settlement EIP-712 domain separator.
     * @return separator Settlement domain separator.
     */
    function domainSeparator() external view returns (bytes32 separator);
}

/**
 * @title ICoWSwapConverter
 * @notice Interface for the CoW Protocol pre-signing converter.
 */
interface ICoWSwapConverter is IConverter {
    /* ERRORS */

    /**
     * @notice Raised when the order UID is already reserved.
     */
    error AlreadyReservedOrder();

    /**
     * @notice Raised when a prepared conversion delay has not elapsed yet.
     */
    error ExecutionDelayNotElapsed();

    /**
     * @notice Raised when the order is already expired.
     */
    error ExpiredOrder();

    /**
     * @notice Raised when the converter does not hold enough unreserved sell token for the order and fee.
     */
    error InsufficientSellBalance();

    /**
     * @notice Raised when the prepared conversion nonce is no longer current.
     */
    error InvalidNonce();

    /**
     * @notice Raised when the sell amount is zero or inconsistent with the converter input.
     */
    error InvalidSellAmount();

    /**
     * @notice Raised when the input token is the vault asset.
     */
    error InvalidTokenIn();

    /**
     * @notice Raised when a reserved order has not expired yet.
     */
    error OrderNotExpired();

    /**
     * @notice Raised when the order expiry is too far in the future.
     */
    error TooFarValidTo();

    /**
     * @notice Raised when an order UID does not reference a reservation.
     */
    error UnknownOrder();

    /* STRUCTS */

    struct Data {
        address sellToken;
        address buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        bytes32 kind;
        bool partiallyFillable;
        bytes32 sellTokenBalance;
        bytes32 buyTokenBalance;
    }

    /**
     * @notice CoW Protocol order parameters provided through converter data.
     * @param sellAmount The sell amount in `tokenIn`.
     * @param buyAmount The buy amount in `tokenOut`.
     * @param validTo The order expiry timestamp.
     * @param appData The CoW Protocol app data hash.
     * @param feeAmount The fee amount in `tokenIn`.
     */
    struct OrderParams {
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
    }

    /**
     * @notice Active sell-balance reservation for an outstanding CoW order.
     * @param token Sell token reserved.
     * @param amount Sell amount plus fee amount reserved.
     * @param validTo Order expiry timestamp.
     */
    struct ReservedOrder {
        address token;
        uint256 amount;
        uint32 validTo;
    }

    /* EVENTS */

    /**
     * @notice Emitted when a conversion request is prepared.
     * @param tokenIn The sell token.
     * @param amountIn Input token amount.
     * @param tokenOut The buy token.
     * @param data Converter-specific route data.
     */
    event PrepareConvert(address indexed tokenIn, uint256 amountIn, address indexed tokenOut, bytes data);

    /**
     * @notice Emitted when a pre-signed CoW Protocol order is created.
     * @param orderUid The pre-signed order UID.
     * @param tokenIn The sell token.
     * @param amountIn Input token amount.
     * @param tokenOut The buy token.
     * @param params The CoW Protocol order parameters.
     */
    event Convert(
        bytes orderUid, address indexed tokenIn, uint256 amountIn, address indexed tokenOut, OrderParams params
    );

    /**
     * @notice Emitted when an expired order reservation is released.
     * @param orderUid The expired order UID.
     * @param token The sell token released.
     * @param amount The released sell amount plus fee amount.
     */
    event ReleaseExpiredOrder(bytes orderUid, address indexed token, uint256 amount);

    /**
     * @notice Emitted when the authorized converter set is replaced.
     * @param converters The new authorized converter addresses.
     */
    event SetConverters(address[] converters);

    /* FUNCTIONS */

    /**
     * @notice Returns the CoW Protocol settlement contract used for order signing.
     * @return settlement The CoW Protocol settlement contract.
     */
    function COW_SWAP_SETTLEMENT() external view returns (address settlement);

    /**
     * @notice Returns the CoW Protocol vault relayer approved to pull sell tokens.
     * @return relayer The CoW Protocol vault relayer.
     */
    function COW_SWAP_VAULT_RELAYER() external view returns (address relayer);

    /**
     * @notice Replaces the set of converters allowed to create orders without the prepared-request delay.
     * @param newConverters The new authorized converter addresses.
     */
    function setConverters(address[] calldata newConverters) external;

    /**
     * @notice Returns when a prepared conversion request can be executed.
     * @param nonce Nonce bucket for the prepared conversion request.
     * @param requestHash Hash of the prepared conversion request.
     * @return timestamp Time when the request can be executed.
     */
    function executableAt(uint256 nonce, bytes32 requestHash) external view returns (uint48 timestamp);

    /**
     * @notice Prepares a conversion request for delayed permissionless execution.
     * @param tokenIn Input token address.
     * @param amountIn Input token amount.
     * @param tokenOut Output token address.
     * @param data Converter-specific route data.
     * @return requestHash Hash of the prepared conversion request.
     */
    function prepareConvert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data)
        external
        returns (bytes32 requestHash);
}

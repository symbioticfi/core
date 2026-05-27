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
     * @notice Raised when the order is already expired.
     */
    error ExpiredOrder();

    /**
     * @notice Raised when the converter does not hold enough unreserved sell token for the order and fee.
     */
    error InsufficientSellBalance();

    /**
     * @notice Raised when the requested buy amount is below the minimum output.
     */
    error InvalidBuyAmount();

    /**
     * @notice Raised when the sell amount is zero or inconsistent with the converter input.
     */
    error InvalidSellAmount();

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
     * @notice Emitted when a pre-signed CoW Protocol order is created.
     * @param orderUid The pre-signed order UID.
     * @param tokenIn The sell token.
     * @param tokenOut The buy token.
     * @param params The CoW Protocol order parameters.
     */
    event Convert(bytes orderUid, address indexed tokenIn, address indexed tokenOut, OrderParams params);

    /**
     * @notice Emitted when an expired order reservation is released.
     * @param orderUid The expired order UID.
     * @param token The sell token released.
     * @param amount The released sell amount plus fee amount.
     */
    event ReleaseExpiredOrder(bytes orderUid, address indexed token, uint256 amount);

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
     * @notice Returns the maximum distance allowed between `block.timestamp` and `validTo`.
     * @return duration Maximum valid-to duration in seconds.
     */
    function MAX_VALID_TO_DURATION() external view returns (uint32 duration);

    /**
     * @notice Returns the sell amount currently reserved for active orders.
     * @param token Sell token address.
     * @return amount Reserved sell amount.
     */
    function reservedSellBalance(address token) external view returns (uint256 amount);

    /**
     * @notice Returns a reserved order by hashed order UID.
     * @param orderUidHash Hash of the order UID.
     * @return token Sell token reserved.
     * @return amount Sell amount plus fee amount reserved.
     * @return validTo Order expiry timestamp.
     */
    function reservedOrder(bytes32 orderUidHash) external view returns (address token, uint256 amount, uint32 validTo);

    /**
     * @notice Releases an expired order reservation.
     * @param orderUid Encoded CoW Protocol order UID.
     */
    function releaseExpiredOrder(bytes calldata orderUid) external;
}

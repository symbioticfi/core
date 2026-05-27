// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {
    COW_SWAP_BALANCE_ERC20,
    COW_SWAP_KIND_SELL,
    COW_SWAP_ORDER_TYPEHASH,
    COW_SWAP_ORDER_UID_LENGTH,
    ICoWSwapConverter,
    ICoWSwapSettlement
} from "../../../interfaces/adapters/common/ICoWSwapConverter.sol";
import {IConverter} from "../../../interfaces/adapters/common/IConverter.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CoWSwapConverter
/// @notice Converter for asynchronous CoW Protocol sell orders via pre-signing.
contract CoWSwapConverter is ICoWSwapConverter {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc ICoWSwapConverter
    address public immutable COW_SWAP_SETTLEMENT;
    /// @inheritdoc ICoWSwapConverter
    address public immutable COW_SWAP_VAULT_RELAYER;
    /// @inheritdoc ICoWSwapConverter
    uint32 public immutable MAX_VALID_TO_DURATION;

    /* STATE VARIABLES */

    /// @inheritdoc ICoWSwapConverter
    mapping(address token => uint256 amount) public reservedSellBalance;
    /// @inheritdoc ICoWSwapConverter
    mapping(bytes32 orderUidHash => ReservedOrder order) public reservedOrder;

    /* CONSTRUCTOR */

    constructor(address cowSwapSettlement, address cowSwapVaultRelayer, uint32 maxValidToDuration) {
        COW_SWAP_SETTLEMENT = cowSwapSettlement;
        COW_SWAP_VAULT_RELAYER = cowSwapVaultRelayer;
        MAX_VALID_TO_DURATION = maxValidToDuration;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IConverter
    function convert(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes calldata data)
        public
    {
        OrderParams memory params = abi.decode(data, (OrderParams));
        if (amountIn == 0 || params.sellAmount + params.feeAmount != amountIn) {
            revert InvalidSellAmount();
        }
        if (params.buyAmount < minAmountOut) {
            revert InvalidBuyAmount();
        }
        if (params.validTo <= block.timestamp) {
            revert ExpiredOrder();
        }
        if (params.validTo > block.timestamp + MAX_VALID_TO_DURATION) {
            revert TooFarValidTo();
        }

        uint256 totalSellAmount = params.sellAmount + params.feeAmount;
        uint256 reserved = reservedSellBalance[tokenIn];
        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        if (balance < reserved || balance - reserved < totalSellAmount) {
            revert InsufficientSellBalance();
        }

        if (IERC20(tokenIn).allowance(address(this), COW_SWAP_VAULT_RELAYER) < totalSellAmount) {
            IERC20(tokenIn).forceApprove(COW_SWAP_VAULT_RELAYER, type(uint256).max);
        }

        bytes memory orderUid = new bytes(COW_SWAP_ORDER_UID_LENGTH);
        _packOrderUidParams(
            orderUid,
            _hash(
                Data({
                    sellToken: tokenIn,
                    buyToken: tokenOut,
                    receiver: address(this),
                    sellAmount: params.sellAmount,
                    buyAmount: params.buyAmount,
                    validTo: params.validTo,
                    appData: params.appData,
                    feeAmount: params.feeAmount,
                    kind: COW_SWAP_KIND_SELL,
                    partiallyFillable: false,
                    sellTokenBalance: COW_SWAP_BALANCE_ERC20,
                    buyTokenBalance: COW_SWAP_BALANCE_ERC20
                }),
                ICoWSwapSettlement(COW_SWAP_SETTLEMENT).domainSeparator()
            ),
            address(this),
            params.validTo
        );

        bytes32 orderUidHash = keccak256(orderUid);
        if (reservedOrder[orderUidHash].token != address(0)) {
            revert AlreadyReservedOrder();
        }
        reservedSellBalance[tokenIn] = reserved + totalSellAmount;
        reservedOrder[orderUidHash] = ReservedOrder({token: tokenIn, amount: totalSellAmount, validTo: params.validTo});

        ICoWSwapSettlement(COW_SWAP_SETTLEMENT).setPreSignature(orderUid, true);

        emit Convert(orderUid, tokenIn, tokenOut, params);
    }

    /// @inheritdoc ICoWSwapConverter
    function releaseExpiredOrder(bytes calldata orderUid) public {
        bytes32 orderUidHash = keccak256(orderUid);
        ReservedOrder memory order = reservedOrder[orderUidHash];
        if (order.token == address(0)) {
            revert UnknownOrder();
        }
        if (block.timestamp <= order.validTo) {
            revert OrderNotExpired();
        }

        delete reservedOrder[orderUidHash];
        reservedSellBalance[order.token] -= order.amount;

        emit ReleaseExpiredOrder(orderUid, order.token, order.amount);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Return the EIP-712 signing hash for the specified order.
    function _hash(Data memory order, bytes32 domainSeparator) internal pure returns (bytes32 orderDigest) {
        bytes32 structHash;
        assembly {
            let dataStart := sub(order, 32)
            let temp := mload(dataStart)
            mstore(dataStart, COW_SWAP_ORDER_TYPEHASH)
            structHash := keccak256(dataStart, 416)
            mstore(dataStart, temp)
        }

        assembly {
            let freeMemoryPointer := mload(0x40)
            mstore(freeMemoryPointer, "\x19\x01")
            mstore(add(freeMemoryPointer, 2), domainSeparator)
            mstore(add(freeMemoryPointer, 34), structHash)
            orderDigest := keccak256(freeMemoryPointer, 66)
        }
    }

    /// @dev Packs order UID parameters into the specified memory location.
    function _packOrderUidParams(bytes memory orderUid, bytes32 orderDigest, address owner, uint32 validTo)
        internal
        pure
    {
        assembly {
            mstore(add(orderUid, 56), validTo)
            mstore(add(orderUid, 52), owner)
            mstore(add(orderUid, 32), orderDigest)
        }
    }
}

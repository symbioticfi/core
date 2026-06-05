// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {
    COW_SWAP_BALANCE_ERC20,
    COW_SWAP_KIND_SELL,
    COW_SWAP_ORDER_TYPEHASH,
    COW_SWAP_ORDER_UID_LENGTH,
    EXECUTION_DELAY,
    ICoWSwapConverter,
    ICoWSwapSettlement,
    MAX_VALID_TO_DURATION
} from "../../../interfaces/adapters/common/ICoWSwapConverter.sol";
import {IConverter} from "../../../interfaces/adapters/common/IConverter.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CoWSwapConverter
/// @notice Converter for asynchronous CoW Protocol sell orders via pre-signing.
contract CoWSwapConverter is OwnableUpgradeable, Nonces, ICoWSwapConverter {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc ICoWSwapConverter
    address public immutable COW_SWAP_SETTLEMENT;
    /// @inheritdoc ICoWSwapConverter
    address public immutable COW_SWAP_VAULT_RELAYER;

    /* STORAGE */

    /// @custom:storage-location erc7201:symbiotic.storage.CoWSwapConverter
    struct CoWSwapConverterStorage {
        mapping(address converter => bool status) isConverter;
        mapping(uint256 nonce => mapping(bytes32 requestHash => uint48 timestamp)) executableAt;
    }

    /// @dev Returns CoW converter storage at the ERC-7201 namespace.
    function _getCoWSwapConverterStorage() internal pure returns (CoWSwapConverterStorage storage $) {
        uint256 slot = erc7201("symbiotic.storage.CoWSwapConverter");
        assembly {
            $.slot := slot
        }
    }

    /* CONSTRUCTOR */

    constructor(address cowSwapSettlement, address cowSwapVaultRelayer) {
        COW_SWAP_SETTLEMENT = cowSwapSettlement;
        COW_SWAP_VAULT_RELAYER = cowSwapVaultRelayer;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc ICoWSwapConverter
    function executableAt(uint256 nonce, bytes32 requestHash) public view returns (uint48 timestamp) {
        return _getCoWSwapConverterStorage().executableAt[nonce][requestHash];
    }

    /// @inheritdoc ICoWSwapConverter
    function isConverter(address converter) public view returns (bool status) {
        return _getCoWSwapConverterStorage().isConverter[converter];
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data) public virtual override {
        OrderParams memory params = abi.decode(data, (OrderParams));
        if (amountIn == 0 || params.sellAmount + params.feeAmount != amountIn) {
            revert InvalidSellAmount();
        }
        if (params.validTo <= block.timestamp) {
            revert ExpiredOrder();
        }
        if (params.validTo > block.timestamp + MAX_VALID_TO_DURATION) {
            revert TooFarValidTo();
        }

        if (!isConverter(msg.sender)) {
            uint48 timestamp = _getCoWSwapConverterStorage()
            .executableAt[nonces(tokenIn)][keccak256(abi.encode(tokenIn, amountIn, tokenOut, data))];
            if (timestamp == 0 || block.timestamp < timestamp) {
                revert ExecutionDelayNotElapsed();
            }
        }
        _useNonce(tokenIn);

        if (IERC20(tokenIn).allowance(address(this), COW_SWAP_VAULT_RELAYER) < amountIn) {
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
        ICoWSwapSettlement(COW_SWAP_SETTLEMENT).setPreSignature(orderUid, true);

        emit Convert(orderUid, tokenIn, amountIn, tokenOut, params);
    }

    /// @inheritdoc ICoWSwapConverter
    function prepareConvert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data)
        public
        virtual
        returns (bytes32 requestHash)
    {
        requestHash = keccak256(abi.encode(tokenIn, amountIn, tokenOut, data));

        CoWSwapConverterStorage storage $ = _getCoWSwapConverterStorage();
        if ($.executableAt[nonces(tokenIn)][requestHash] > 0) {
            revert AlreadyReservedOrder();
        }
        $.executableAt[nonces(tokenIn)][requestHash] = uint48(block.timestamp) + EXECUTION_DELAY;

        emit PrepareConvert(tokenIn, amountIn, tokenOut, data);
    }

    /// @inheritdoc ICoWSwapConverter
    function setConverterStatus(address converter, bool status) public onlyOwner {
        _getCoWSwapConverterStorage().isConverter[converter] = status;

        emit SetConverterStatus(converter, status);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Return the EIP-712 signing hash for the specified order.
    ///
    /// @param order The order to compute the EIP-712 signing hash for.
    /// @param domainSeparator The EIP-712 domain separator to use.
    /// @return orderDigest The 32 byte EIP-712 struct hash.
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

    /// @dev Packs order UID parameters into the specified memory location. The
    /// result is equivalent to `abi.encodePacked(...)` with the difference that
    /// it allows re-using the memory for packing the order UID.
    ///
    /// @param orderUid The buffer pack the order UID parameters into.
    /// @param orderDigest The EIP-712 struct digest derived from the order
    /// parameters.
    /// @param owner The address of the user who owns this order.
    /// @param validTo The epoch time at which the order will stop being valid.
    function _packOrderUidParams(bytes memory orderUid, bytes32 orderDigest, address owner, uint48 validTo)
        internal
        pure
    {
        assembly {
            mstore(add(orderUid, 56), validTo)
            mstore(add(orderUid, 52), owner)
            mstore(add(orderUid, 32), orderDigest)
        }
    }

    /* INITIALIZATION */

    /// @dev Registers the initial converters allowed to create orders without the prepared-request delay.
    function __CoWSwapConverter_init(address[] memory initConverters) internal virtual {
        CoWSwapConverterStorage storage $ = _getCoWSwapConverterStorage();
        for (uint256 i; i < initConverters.length; ++i) {
            $.isConverter[initConverters[i]] = true;
        }
    }
}

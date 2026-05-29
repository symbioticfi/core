// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "../Adapter.sol";

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
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CoWSwapConverter
/// @notice Converter for asynchronous CoW Protocol sell orders via pre-signing.
abstract contract CoWSwapConverter is Adapter, Nonces, ICoWSwapConverter {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc ICoWSwapConverter
    address public immutable COW_SWAP_SETTLEMENT;
    /// @inheritdoc ICoWSwapConverter
    address public immutable COW_SWAP_VAULT_RELAYER;

    /* STATE VARIABLES */

    /// @inheritdoc ICoWSwapConverter
    mapping(uint256 nonce => mapping(bytes32 requestHash => uint48 timestamp)) public executableAt;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory, address cowSwapSettlement, address cowSwapVaultRelayer)
        Adapter(vaultFactory, adapterFactory)
    {
        COW_SWAP_SETTLEMENT = cowSwapSettlement;
        COW_SWAP_VAULT_RELAYER = cowSwapVaultRelayer;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IConverter
    function convert(address tokenIn, uint256 amountIn, bytes calldata data) public virtual override {
        if (tokenIn == IERC4626(vault).asset()) {
            revert InvalidTokenIn();
        }

        if (owner() != msg.sender) {
            uint48 timestamp = executableAt[nonces(tokenIn)][keccak256(abi.encode(tokenIn, amountIn, data))];
            if (timestamp == 0) {
                revert InvalidNonce();
            }
            if (block.timestamp < timestamp) {
                revert ExecutionDelayNotElapsed();
            }
        }
        _useNonce(tokenIn);

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

        uint256 totalSellAmount = params.sellAmount + params.feeAmount;
        if (IERC20(tokenIn).balanceOf(address(this)) < totalSellAmount) {
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
                    buyToken: _convertTokenOut(),
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

        emit Convert(orderUid, tokenIn, amountIn, params);
    }

    /// @inheritdoc ICoWSwapConverter
    function prepareConvert(address tokenIn, uint256 amountIn, bytes calldata data)
        public
        virtual
        returns (bytes32 requestHash)
    {
        requestHash = keccak256(abi.encode(tokenIn, amountIn, data));
        executableAt[nonces(tokenIn)][requestHash] = uint48(block.timestamp + EXECUTION_DELAY);

        emit PrepareConvert(tokenIn, amountIn, data);
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

    /// @dev Returns the token expected as CoW swap output.
    function _convertTokenOut() internal view virtual returns (address) {
        return IERC4626(vault).asset();
    }
}

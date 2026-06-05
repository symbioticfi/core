// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

/// @dev Precision used for discount values expressed in ppm.
uint256 constant DISCOUNT_PRECISION = 10 ** 6;

/// @dev Maximum number of tokens-to-redeem configurable for the vault.
uint256 constant MAX_TOKENS_TO_REDEEM = 15;

/// @dev EIP-712 typehash for signed adapter swap legs.
bytes32 constant SIGNED_SWAP_TYPEHASH = keccak256(
    "SignedSwap(address recipient,address tokenIn,uint256 amountIn,uint256 amountOut,address caller,address signer,uint256 nonce,uint48 deadline)"
);

/// @dev EIP-712 typehash for reusable signed discount policies.
bytes32 constant DISCOUNT_TYPEHASH = keccak256(
    "Discount(address tokenToRedeem,uint256 discount,address signer,address protocol,uint256 nonce,uint48 deadline)"
);

/// @dev EIP-712 typehash for protocol-wrapped discount swaps.
bytes32 constant DISCOUNT_SWAP_TYPEHASH = keccak256(
    "DiscountSwap(Discount discount,bytes signerSignature,uint48 protocolDeadline)"
    "Discount(address tokenToRedeem,uint256 discount,address signer,address protocol,uint256 nonce,uint48 deadline)"
);

/**
 * @title ILiquidLaneAdapter
 * @notice Interface for the liquidity lane adapter, bound to a single vault.
 */
interface ILiquidLaneAdapter is IAdapter {
    /* ERRORS */

    /**
     * @notice Raised when a signed-swap nonce was already consumed.
     */
    error AlreadyUsedNonce();

    /**
     * @notice Raised when the caller is not allowed to prefund acquisition balances.
     */
    error DepositNotAllowed();

    /**
     * @notice Raised when a signed swap is already expired.
     */
    error ExpiredSwap();

    /**
     * @notice Raised when an account with assets is being removed.
     */
    error AccountHasAssets();

    /**
     * @notice Raised when the account is not authorized to initiate the swap.
     */
    error InvalidAccount();

    /**
     * @notice Raised when the caller is not authorized for the requested action.
     */
    error InvalidCaller();

    /**
     * @notice Raised when VaultV2 cannot allocate enough vault assets to the adapter.
     */
    error InsufficientAllocate();

    /**
     * @notice Raised when a discount configuration is invalid.
     */
    error InvalidDiscount();

    /**
     * @notice Raised when an oracle configuration is invalid.
     */
    error InvalidOracle();

    /**
     * @notice Raised when a receiver is zero.
     */
    error InvalidReceiver();

    /**
     * @notice Raised when a signed swap signature is invalid.
     */
    error InvalidSignature();

    /**
     * @notice Raised when a swap rate violates the configured minimum.
     */
    error InvalidSwapRate();

    /**
     * @notice Raised when the token-to-redeem is invalid.
     */
    error InvalidTokenToRedeem();

    /**
     * @notice Raised when an account would exceed the configured token limit.
     */
    error LimitExceeded();

    /**
     * @notice Raised when adding a token would exceed the configured maximum.
     */
    error TooManyTokensToRedeem();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the liquidity lane adapter.
     * @param pauser Address allowed to pause swaps.
     * @param unpauser Address allowed to unpause swaps.
     */
    struct InitParams {
        address pauser;
        address unpauser;
    }

    /**
     * @notice Direct authorized swap payload.
     * @param recipient Recipient of the vault-asset output.
     * @param tokenIn Token-to-redeem consumed by the swap.
     * @param amountIn Token-to-redeem amount consumed by the swap.
     * @param amountOut Vault-asset amount requested from the vault.
     */
    struct Swap {
        address recipient;
        address tokenIn;
        uint256 amountIn;
        uint256 amountOut;
    }

    /**
     * @notice Delegated swap payload signed by an authorized signer.
     * @param recipient Recipient of the vault-asset output.
     * @param tokenIn Token-to-redeem consumed by the swap.
     * @param amountIn Token-to-redeem amount consumed by the swap.
     * @param amountOut Vault-asset amount requested from the vault.
     * @param caller Caller authorized to submit the signed swap onchain.
     * @param signer Authorized market maker, filler, or curator that signed the swap.
     * @param nonce Nonce consumed for replay protection.
     * @param deadline Signed-swap expiry timestamp.
     */
    struct SignedSwap {
        address recipient;
        address tokenIn;
        uint256 amountIn;
        uint256 amountOut;
        address caller;
        address signer;
        uint256 nonce;
        uint48 deadline;
    }

    /**
     * @notice Reusable signed discount policy for one redemption pair.
     * @param tokenToRedeem Token-to-redeem consumed by the swap.
     * @param discount Discount in ppm.
     * @param signer Authorized market maker, filler, or curator that signed the discount.
     * @param protocol Protocol signer that will add the short-lived cosign.
     * @param nonce Nonce consumed for replay protection.
     * @param deadline Discount expiry timestamp.
     */
    struct Discount {
        address tokenToRedeem;
        uint256 discount;
        address signer;
        address protocol;
        uint256 nonce;
        uint48 deadline;
    }

    /**
     * @notice Short-lived protocol-authorized wrapper for a reusable discount.
     * @param discount Reusable signed discount policy.
     * @param signerSignature Signature over the reusable `Discount`.
     * @param protocolDeadline Fresh short-lived protocol expiry timestamp.
     */
    struct DiscountSwap {
        Discount discount;
        bytes signerSignature;
        uint48 protocolDeadline;
    }

    /* EVENTS */

    /**
     * @notice Emitted when the adapter is initialized.
     * @param params Initialization parameters.
     */
    event Initialize(InitParams params);

    /**
     * @notice Emitted when a token minimum discount is updated.
     * @param tokenToRedeem The token-to-redeem address.
     * @param newMinDiscount The new minimum discount in ppm.
     */
    event SetMinDiscount(address indexed tokenToRedeem, uint256 newMinDiscount);

    /**
     * @notice Emitted when a token vault-asset limit is updated.
     * @param tokenToRedeem The token-to-redeem address.
     * @param newLimit The new vault-asset limit.
     */
    event SetLimit(address indexed tokenToRedeem, uint256 newLimit);

    /**
     * @notice Emitted when the market maker is updated.
     * @param newMarketMaker The new market maker.
     * @param newCanAcquire Whether the market maker may prefund acquisition balances.
     */
    event SetMarketMaker(address indexed newMarketMaker, bool newCanAcquire);

    /**
     * @notice Emitted when the pauser is updated.
     * @param newPauser The new pauser address.
     */
    event SetPauser(address indexed newPauser);

    /**
     * @notice Emitted when the unpauser is updated.
     * @param newUnpauser The new unpauser address.
     */
    event SetUnpauser(address indexed newUnpauser);

    /**
     * @notice Emitted when a filler authorization is updated.
     * @param marketMaker The market maker address.
     * @param filler The filler address.
     * @param isAuthorized Whether the filler is authorized.
     */
    event SetFiller(address indexed marketMaker, address indexed filler, bool isAuthorized);

    /**
     * @notice Emitted when acquisition assets are deposited.
     * @param who The depositor address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param amount The asset amount deposited.
     */
    event DepositToAcquire(address indexed who, address indexed tokenToRedeem, uint256 amount);

    /**
     * @notice Emitted when a swap is executed.
     * @param swap The executed swap payload.
     */
    event DoSwap(Swap swap);

    /**
     * @notice Emitted when acquisition assets are withdrawn.
     * @param who The withdrawing address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param amount The asset amount withdrawn.
     */
    event WithdrawToAcquire(address indexed who, address indexed tokenToRedeem, uint256 amount);

    /**
     * @notice Emitted when a signed-swap nonce is invalidated.
     * @param tokenToRedeem The token-to-redeem address.
     * @param nonce The invalidated nonce.
     */
    event InvalidateNonce(address indexed tokenToRedeem, uint256 indexed nonce);

    /**
     * @notice Emitted when an account updates its token-in receiver.
     * @param who The account setting the receiver.
     * @param receiver The receiver address.
     */
    event SetReceiver(address indexed who, address indexed receiver);

    /**
     * @notice Emitted when a token-to-redeem is configured.
     * @param tokenToRedeem The token-to-redeem address.
     * @param account The created account address.
     */
    event AddTokenToRedeem(address indexed tokenToRedeem, address indexed account);

    /**
     * @notice Emitted when a token-to-redeem is removed.
     * @param tokenToRedeem The token-to-redeem address.
     */
    event RemoveTokenToRedeem(address indexed tokenToRedeem);

    /* FUNCTIONS */

    /**
     * @notice Returns the configured market maker.
     * @return marketMakerAddress The configured market maker.
     */
    function marketMaker() external view returns (address marketMakerAddress);

    /**
     * @notice Returns whether the market maker may prefund acquisition balances.
     * @return canAcquire Whether market-maker acquisition is enabled.
     */
    function marketMakerCanAcquire() external view returns (bool canAcquire);

    /**
     * @notice Returns the prefunded acquisition balance for an account and token.
     * @param tokenToRedeem The token-to-redeem address.
     * @param account The account whose acquisition balance is queried.
     * @return amount The acquisition balance.
     */
    function acquireBalance(address tokenToRedeem, address account) external view returns (uint256 amount);

    /**
     * @notice Returns the maximum vault-asset output currently available for a token swap.
     * @param tokenToRedeem The token-to-redeem address.
     * @return amount The maximum vault-asset output.
     */
    function getMaxAssets(address tokenToRedeem) external returns (uint256 amount);

    /**
     * @notice Returns the maximum oracle-backed swap rate after the configured minimum discount.
     * @param tokenToRedeem The token-to-redeem address.
     * @return rate The maximum 1e18-scaled swap rate.
     */
    function getMaxRate(address tokenToRedeem) external view returns (uint256 rate);

    /**
     * @notice Returns the oracle-derived vault-asset output for a token-to-redeem amount.
     * @param tokenToRedeem The priced token-to-redeem.
     * @param amountIn The input amount.
     * @return amountOut The oracle-derived vault-asset output amount.
     */
    function getAmountOut(address tokenToRedeem, uint256 amountIn) external view returns (uint256 amountOut);

    /**
     * @notice Returns the number of configured tokens-to-redeem.
     * @return length The number of configured tokens-to-redeem.
     */
    function getTokensToRedeemLength() external view returns (uint256 length);

    /**
     * @notice Returns a configured token-to-redeem by index.
     * @param index The token index.
     * @return tokenToRedeem The configured token-to-redeem.
     */
    function tokensToRedeem(uint256 index) external view returns (address tokenToRedeem);

    /**
     * @notice Returns whether an address is an authorized filler for a market maker.
     * @param marketMaker The market maker address.
     * @param filler The filler address.
     * @return status Whether the filler is authorized.
     */
    function isFiller(address marketMaker, address filler) external view returns (bool status);

    /**
     * @notice Returns the configured minimum swap discount for a token.
     * @param tokenToRedeem The token-to-redeem address.
     * @return ppm The minimum discount in ppm.
     */
    function minDiscount(address tokenToRedeem) external view returns (uint256 ppm);

    /**
     * @notice Returns the configured vault-funded asset limit for a token.
     * @param tokenToRedeem The token-to-redeem address.
     * @return amount The vault-funded asset limit.
     */
    function limit(address tokenToRedeem) external view returns (uint256 amount);

    /**
     * @notice Returns whether a signed-swap nonce was already used.
     * @param tokenToRedeem The token-to-redeem address.
     * @param nonce The nonce to query.
     * @return used Whether the nonce was already consumed.
     */
    function isUsedNonce(address tokenToRedeem, uint256 nonce) external view returns (bool used);

    /**
     * @notice Returns the created account for a token-to-redeem.
     * @param tokenToRedeem The token-to-redeem address.
     * @return account The account address.
     */
    function accounts(address tokenToRedeem) external view returns (address account);

    /**
     * @notice Returns the token-in receiver configured by an account.
     * @param who The account whose receiver is queried.
     * @return receiverAddress The configured receiver.
     */
    function receiver(address who) external view returns (address receiverAddress);

    /**
     * @notice Returns the address allowed to pause swaps.
     * @return pauserAddress The pauser address.
     */
    function pauser() external view returns (address pauserAddress);

    /**
     * @notice Returns the address allowed to unpause swaps.
     * @return unpauserAddress The unpauser address.
     */
    function unpauser() external view returns (address unpauserAddress);

    /**
     * @notice Returns whether swaps are globally paused.
     * @return status Whether swaps are paused.
     */
    function paused() external view returns (bool status);

    /**
     * @notice Prefunds acquisition balances with vault assets.
     * @param tokenToRedeem The token-to-redeem address.
     * @param amount The asset amount to deposit.
     */
    function depositToAcquire(address tokenToRedeem, uint256 amount) external;

    /**
     * @notice Sets the token-in receiver for the caller.
     * @param newReceiver The receiver address.
     */
    function setReceiver(address newReceiver) external;

    /**
     * @notice Sets filler authorization for the market maker.
     * @param filler The filler address.
     * @param isAuthorized Whether the filler is authorized.
     */
    function setFiller(address filler, bool isAuthorized) external;

    /**
     * @notice Marks a signed-swap nonce as used.
     * @param tokenToRedeem The token-to-redeem address.
     * @param nonce The nonce to invalidate.
     */
    function invalidateNonce(address tokenToRedeem, uint256 nonce) external;

    /**
     * @notice Withdraws prefunded acquisition balance.
     * @param tokenToRedeem The token-to-redeem address.
     * @param amount The asset amount to withdraw.
     */
    function withdrawToAcquire(address tokenToRedeem, uint256 amount) external;

    /**
     * @notice Sets the market maker and acquisition permissions.
     * @param newMarketMaker The new market maker.
     * @param newCanAcquire Whether the market maker may prefund acquisition balances.
     */
    function setMarketMaker(address newMarketMaker, bool newCanAcquire) external;

    /**
     * @notice Configures a token-to-redeem and creates its account.
     * @param tokenToRedeem The token-to-redeem address.
     */
    function addTokenToRedeem(address tokenToRedeem) external;

    /**
     * @notice Removes a configured token-to-redeem.
     * @param tokenToRedeem The token-to-redeem address.
     */
    function removeTokenToRedeem(address tokenToRedeem) external;

    /**
     * @notice Sets the vault-funded asset limit for a token.
     * @param tokenToRedeem The token-to-redeem address.
     * @param newLimit The new vault-funded asset limit.
     */
    function setLimit(address tokenToRedeem, uint256 newLimit) external;

    /**
     * @notice Sets the minimum swap discount for a token.
     * @param tokenToRedeem The token-to-redeem address.
     * @param newMinDiscount The new minimum discount in ppm.
     */
    function setMinDiscount(address tokenToRedeem, uint256 newMinDiscount) external;

    /**
     * @notice Sets the address allowed to pause swaps.
     * @param newPauser The new pauser address.
     */
    function setPauser(address newPauser) external;

    /**
     * @notice Sets the address allowed to unpause swaps.
     * @param newUnpauser The new unpauser address.
     */
    function setUnpauser(address newUnpauser) external;

    /**
     * @notice Pauses swaps.
     */
    function pause() external;

    /**
     * @notice Unpauses swaps.
     */
    function unpause() external;

    /**
     * @notice Executes a direct market-maker swap.
     * @param swap The swap payload.
     */
    function swap(Swap calldata swap) external;

    /**
     * @notice Executes a delegated market-maker swap.
     * @param signedSwap The signed swap payload.
     * @param signature The EIP-712 signature.
     */
    function swap(SignedSwap calldata signedSwap, bytes calldata signature) external;

    /**
     * @notice Executes a reusable discount-backed swap.
     * @param discountSwap The short-lived protocol-authorized discount swap payload.
     * @param protocolSignature The protocol EIP-712 signature over `discountSwap`.
     * @param recipient Recipient of the vault-asset output.
     * @param amountIn Token-to-redeem amount consumed by the swap.
     * @return amountOut Vault-asset amount paid by the vault.
     */
    function swap(
        DiscountSwap calldata discountSwap,
        bytes calldata protocolSignature,
        address recipient,
        uint256 amountIn
    ) external returns (uint256 amountOut);
}

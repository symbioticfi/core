// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

/// @dev Precision used for discount values expressed in ppm.
uint256 constant DISCOUNT_PRECISION = 10 ** 6;

/// @dev Maximum number of tokens-to-redeem configurable per vault.
uint256 constant MAX_TOKENS_TO_REDEEM = 15;

/// @dev EIP-712 typehash for signed adapter swap legs.
bytes32 constant SIGNED_SWAP_TYPEHASH = keccak256(
    "SignedSwap(address recipient,address vault,address tokenIn,uint256 amountIn,uint256 amountOut,address caller,address signer,uint256 nonce,uint256 deadline)"
);

/// @dev EIP-712 typehash for reusable signed discount policies.
bytes32 constant DISCOUNT_TYPEHASH = keccak256(
    "Discount(address vault,address tokenToRedeem,uint256 discount,address signer,address protocol,uint256 nonce,uint48 deadline)"
);

/// @dev EIP-712 typehash for protocol-wrapped discount swaps.
bytes32 constant DISCOUNT_SWAP_TYPEHASH = keccak256(
    "DiscountSwap(Discount discount,bytes signerSignature,uint48 protocolDeadline)"
    "Discount(address vault,address tokenToRedeem,uint256 discount,address signer,address protocol,uint256 nonce,uint48 deadline)"
);

/**
 * @title ILiquidityLaneAdapter
 * @notice Interface for the liquidity lane adapter.
 */
interface ILiquidityLaneAdapter is IAdapter {
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
     * @notice Raised when VaultV2 cannot allocate enough collateral to the adapter.
     */
    error InsufficientAllocation();

    /**
     * @notice Raised when the account is not authorized to initiate the swap.
     */
    error InvalidAccount();

    /**
     * @notice Raised when an account beacon cannot be created or upgraded.
     */
    error InvalidAccountBeacon();

    /**
     * @notice Raised when the caller is not authorized for the requested action.
     */
    error InvalidCaller();

    /**
     * @notice Raised when a vault-funded collateral draw exceeds the configured limit.
     */
    error InvalidCollateralOut();

    /**
     * @notice Raised when a discount configuration is invalid.
     */
    error InvalidDiscount();

    /**
     * @notice Raised when a vault token limit is invalid.
     */
    error InvalidLimit();

    /**
     * @notice Raised when an oracle configuration is invalid.
     */
    error InvalidOracle();

    /**
     * @notice Raised when a receiver is zero.
     */
    error InvalidReceiver();

    /**
     * @notice Raised when the redemption token is invalid.
     */
    error InvalidRedemptionToken();

    /**
     * @notice Raised when the provided RWA amount is invalid.
     */
    error InvalidRwaAmount();

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
     * @notice Raised when swaps are paused for the vault.
     */
    error Paused();

    /* STRUCTS */

    /**
     * @notice Direct authorized swap payload.
     * @param recipient Recipient of the collateral output.
     * @param vault Vault used for the swap.
     * @param tokenIn Token-to-redeem consumed by the swap.
     * @param amountIn Token-to-redeem amount consumed by the swap.
     * @param amountOut Collateral amount requested from the vault.
     */
    struct Swap {
        address recipient;
        address vault;
        address tokenIn;
        uint256 amountIn;
        uint256 amountOut;
    }

    /**
     * @notice Delegated swap payload signed by an authorized signer.
     * @param recipient Recipient of the collateral output.
     * @param vault Vault used for the swap.
     * @param tokenIn Token-to-redeem consumed by the swap.
     * @param amountIn Token-to-redeem amount consumed by the swap.
     * @param amountOut Collateral amount requested from the vault.
     * @param caller Caller authorized to submit the signed swap onchain.
     * @param signer Authorized market maker, filler, or curator that signed the swap.
     * @param nonce Nonce consumed for replay protection.
     * @param deadline Signed-swap expiry timestamp.
     */
    struct SignedSwap {
        address recipient;
        address vault;
        address tokenIn;
        uint256 amountIn;
        uint256 amountOut;
        address caller;
        address signer;
        uint256 nonce;
        uint256 deadline;
    }

    /**
     * @notice Reusable signed discount policy for one vault redemption pair.
     * @param vault Vault used for the swap.
     * @param tokenToRedeem Token-to-redeem consumed by the swap.
     * @param discount Discount in ppm.
     * @param signer Authorized market maker, filler, or curator that signed the discount.
     * @param protocol Protocol signer that will add the short-lived cosign.
     * @param nonce Nonce consumed for replay protection.
     * @param deadline Discount expiry timestamp.
     */
    struct Discount {
        address vault;
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
     * @notice Emitted when the adapter owner is initialized.
     * @param owner The initial owner.
     */
    event Initialize(address owner);

    /**
     * @notice Emitted when a token-to-redeem account beacon is set.
     * @param tokenToRedeem The token-to-redeem address.
     * @param beacon The account beacon.
     */
    event SetAccountBeacon(address indexed tokenToRedeem, address indexed beacon);

    /**
     * @notice Emitted when a redemption-token converter is set.
     * @param redemptionToken The redemption token.
     * @param collateralToken The collateral token.
     * @param conversionAdapter The converter address.
     */
    event SetConversionAdapter(
        address indexed redemptionToken, address indexed collateralToken, address indexed conversionAdapter
    );

    /**
     * @notice Emitted when the default maximum conversion discount is updated.
     * @param newGlobalMaxDiscount The new default maximum conversion discount in ppm.
     */
    event SetGlobalMaxDiscount(uint256 newGlobalMaxDiscount);

    /**
     * @notice Emitted when a vault token minimum discount is updated.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param newMinDiscount The new minimum discount in ppm.
     */
    event SetMinDiscount(address indexed vault, address indexed tokenToRedeem, uint256 newMinDiscount);

    /**
     * @notice Emitted when a vault token collateral limit is updated.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param newLimit The new collateral limit.
     */
    event SetLimit(address indexed vault, address indexed tokenToRedeem, uint256 newLimit);

    /**
     * @notice Emitted when a token oracle is set.
     * @param token The priced token.
     * @param oracle The oracle address.
     */
    event SetOracle(address indexed token, address indexed oracle);

    /**
     * @notice Emitted when a pair-specific maximum conversion discount is updated.
     * @param tokenIn The redemption token.
     * @param tokenOut The collateral token.
     * @param newPairMaxDiscount The new pair-specific maximum discount in ppm.
     */
    event SetPairMaxDiscount(address indexed tokenIn, address indexed tokenOut, uint256 newPairMaxDiscount);

    /**
     * @notice Emitted when a vault market maker is updated.
     * @param vault The vault address.
     * @param newMarketMaker The new market maker.
     * @param newCanAcquire Whether the market maker may prefund acquisition balances.
     */
    event SetMarketMaker(address indexed vault, address indexed newMarketMaker, bool newCanAcquire);

    /**
     * @notice Emitted when a filler authorization is updated.
     * @param vault The vault address.
     * @param marketMaker The market maker address.
     * @param filler The filler address.
     * @param isAuthorized Whether the filler is authorized.
     */
    event SetFiller(address indexed vault, address indexed marketMaker, address indexed filler, bool isAuthorized);

    /**
     * @notice Emitted when a vault pause status is updated.
     * @param vault The vault address.
     * @param isPaused Whether swaps are paused.
     */
    event SetPauseStatus(address indexed vault, bool isPaused);

    /**
     * @notice Emitted when acquisition collateral is deposited.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param amount The collateral amount deposited.
     */
    event DepositToAcquire(address indexed vault, address indexed tokenToRedeem, uint256 amount);

    /**
     * @notice Emitted when a swap is executed.
     * @param swap The executed swap payload.
     */
    event DoSwap(Swap swap);

    /**
     * @notice Emitted when redemption proceeds are sent through a converter.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param redemptionToken The token being converted.
     * @param redemptionAmount The redemption-token amount converted.
     */
    event ConvertRedemption(
        address indexed vault, address indexed tokenToRedeem, address indexed redemptionToken, uint256 redemptionAmount
    );

    /**
     * @notice Emitted when acquisition collateral is withdrawn.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param amount The collateral amount withdrawn.
     */
    event WithdrawToAcquire(address indexed vault, address indexed tokenToRedeem, uint256 amount);

    /**
     * @notice Emitted when a signed-swap nonce is invalidated.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param nonce The invalidated nonce.
     */
    event InvalidateNonce(address indexed vault, address indexed tokenToRedeem, uint256 indexed nonce);

    /**
     * @notice Emitted when an account updates its token-in receiver.
     * @param who The account setting the receiver.
     * @param receiver The receiver address.
     */
    event SetReceiver(address indexed who, address indexed receiver);

    /**
     * @notice Emitted when collateral is allocated to the adapter.
     * @param amount The allocated collateral amount.
     */
    event Allocate(uint256 amount);

    /**
     * @notice Emitted when collateral is deallocated from the adapter.
     * @param requestedAmount The requested deallocation amount.
     * @param deallocated The actual deallocated amount.
     */
    event Deallocate(uint256 requestedAmount, uint256 deallocated);

    /* FUNCTIONS */

    /**
     * @notice Returns the configured market maker for a vault.
     * @param vault The vault address.
     * @return marketMakerAddress The configured market maker.
     */
    function marketMaker(address vault) external view returns (address);

    /**
     * @notice Returns whether the market maker may prefund acquisition balances for a vault.
     * @param vault The vault address.
     * @return canAcquire Whether market-maker acquisition is enabled.
     */
    function marketMakerCanAcquire(address vault) external view returns (bool);

    /**
     * @notice Returns the curator-prefunded acquisition balance for a vault token.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @return amount The curator acquisition balance.
     */
    function curatorAcquireBalance(address vault, address tokenToRedeem) external view returns (uint256);

    /**
     * @notice Returns the maximum collateral output currently available for a vault token swap.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @return amount The maximum collateral output.
     */
    function getMaxAssets(address vault, address tokenToRedeem) external view returns (uint256);

    /**
     * @notice Returns the maximum oracle-backed swap rate after the configured minimum discount.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @return rate The maximum 1e18-scaled swap rate.
     */
    function getMaxRate(address vault, address tokenToRedeem) external view returns (uint256);

    /**
     * @notice Returns the oracle-derived output amount between two tokens.
     * @param tokenIn The priced input token.
     * @param tokenOut The priced output token.
     * @param amountIn The input amount.
     * @return amountOut The oracle-derived output amount.
     */
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);

    /**
     * @notice Returns the deterministic account for a vault and token-to-redeem pair.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @return account The deterministic account address.
     */
    function getAccount(address vault, address tokenToRedeem) external view returns (address);

    /**
     * @notice Returns the number of configured tokens-to-redeem for a vault.
     * @param vault The vault address.
     * @return length The number of configured tokens-to-redeem.
     */
    function getTokensToRedeemLength(address vault) external view returns (uint256);

    /**
     * @notice Returns whether an address is an authorized filler for a market maker.
     * @param marketMaker The market maker address.
     * @param filler The filler address.
     * @return status Whether the filler is authorized.
     */
    function isFiller(address marketMaker, address filler) external view returns (bool status);

    /**
     * @notice Returns the configured minimum swap discount for a vault token.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @return ppm The minimum discount in ppm.
     */
    function minDiscount(address vault, address tokenToRedeem) external view returns (uint256);

    /**
     * @notice Returns the configured vault-funded collateral limit for a vault token.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @return amount The collateral limit.
     */
    function limit(address vault, address tokenToRedeem) external view returns (uint256);

    /**
     * @notice Returns whether swaps are paused for a vault.
     * @param vault The vault address.
     * @return paused Whether swaps are paused.
     */
    function isPaused(address vault) external view returns (bool);

    /**
     * @notice Returns whether a signed-swap nonce was already used.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param nonce The nonce to query.
     * @return used Whether the nonce was already consumed.
     */
    function isUsedNonce(address vault, address tokenToRedeem, uint256 nonce) external view returns (bool);

    /**
     * @notice Returns the default maximum conversion discount in ppm.
     * @return ppm The default maximum conversion discount.
     */
    function globalMaxConvertDiscount() external view returns (uint256 ppm);

    /**
     * @notice Returns the beacon used for deterministic redemption accounts of a token-to-redeem.
     * @param tokenToRedeem The token-to-redeem address.
     * @return beacon The beacon address.
     */
    function accountBeacons(address tokenToRedeem) external view returns (address beacon);

    /**
     * @notice Returns the oracle used for a token.
     * @param token The priced token.
     * @return oracle The oracle address.
     */
    function oracles(address token) external view returns (address oracle);

    /**
     * @notice Returns the converter used for a redemption-token and collateral-token pair.
     * @param redemptionToken The redemption token.
     * @param collateralToken The collateral token.
     * @return converter The converter address.
     */
    function converters(address redemptionToken, address collateralToken) external view returns (address converter);

    /**
     * @notice Returns the pair-specific maximum conversion discount in ppm.
     * @param tokenIn The redemption token.
     * @param tokenOut The collateral token.
     * @return ppm The pair-specific maximum conversion discount.
     */
    function pairMaxConvertDiscount(address tokenIn, address tokenOut) external view returns (uint256 ppm);

    /**
     * @notice Returns the prefunded acquisition balance for a market maker and token.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param marketMaker The market maker address.
     * @return amount The market-maker acquisition balance.
     */
    function marketMakerAcquireBalances(address vault, address tokenToRedeem, address marketMaker)
        external
        view
        returns (uint256);

    /**
     * @notice Returns the token-in receiver configured by an account.
     * @param who The account whose receiver is queried.
     * @return receiverAddress The configured receiver.
     */
    function receiver(address who) external view returns (address receiverAddress);

    /**
     * @notice Converts redemption proceeds held by the deterministic account into vault collateral.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param redemptionToken The token currently held by the account.
     * @param redemptionAmount The redemption-token amount to convert.
     * @param data Converter-specific route data.
     */
    function convertRedemption(
        address vault,
        address tokenToRedeem,
        address redemptionToken,
        uint256 redemptionAmount,
        bytes calldata data
    ) external;

    /**
     * @notice Prefunds acquisition balances with vault collateral.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param amount The collateral amount to deposit.
     */
    function depositToAcquire(address vault, address tokenToRedeem, uint256 amount) external;

    /**
     * @notice Sets the token-in receiver for the caller.
     * @param newReceiver The receiver address.
     */
    function setReceiver(address newReceiver) external;

    /**
     * @notice Sets filler authorization for the vault market maker.
     * @param vault The vault address.
     * @param filler The filler address.
     * @param isAuthorized Whether the filler is authorized.
     */
    function setFiller(address vault, address filler, bool isAuthorized) external;

    /**
     * @notice Marks a signed-swap nonce as used.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param nonce The nonce to invalidate.
     */
    function invalidateNonce(address vault, address tokenToRedeem, uint256 nonce) external;

    /**
     * @notice Withdraws prefunded acquisition balance.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param amount The collateral amount to withdraw.
     */
    function withdrawToAcquire(address vault, address tokenToRedeem, uint256 amount) external;

    /**
     * @notice Sets the market maker and acquisition permissions for a vault.
     * @param vault The vault address.
     * @param newMarketMaker The new market maker.
     * @param newCanAcquire Whether the market maker may prefund acquisition balances.
     */
    function setMakerMaker(address vault, address newMarketMaker, bool newCanAcquire) external;

    /**
     * @notice Sets the vault-funded collateral limit for a vault token.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param newLimit The new collateral limit.
     */
    function setLimit(address vault, address tokenToRedeem, uint256 newLimit) external;

    /**
     * @notice Sets the minimum swap discount for a vault token.
     * @param vault The vault address.
     * @param tokenToRedeem The token-to-redeem address.
     * @param newMinDiscount The new minimum discount in ppm.
     */
    function setMinDiscount(address vault, address tokenToRedeem, uint256 newMinDiscount) external;

    /**
     * @notice Sets the paused status for a vault.
     * @param vault The vault address.
     * @param newPauseStatus The new paused status.
     */
    function setPauseStatus(address vault, bool newPauseStatus) external;

    /**
     * @notice Sets the account beacon for a token-to-redeem.
     * @param tokenToRedeem The token-to-redeem address.
     * @param beacon The account beacon.
     */
    function setAccountBeacon(address tokenToRedeem, address beacon) external;

    /**
     * @notice Sets the converter used for a redemption-token to collateral pair.
     * @param redemptionToken The redemption token.
     * @param collateralToken The collateral token.
     * @param conversionAdapter The converter address.
     */
    function setConversionAdapter(address redemptionToken, address collateralToken, address conversionAdapter) external;

    /**
     * @notice Sets the default maximum conversion discount.
     * @param newGlobalMaxDiscount The new default maximum conversion discount in ppm.
     */
    function setGlobalMaxDiscount(uint256 newGlobalMaxDiscount) external;

    /**
     * @notice Sets the token oracle used for USD pricing.
     * @param token The priced token.
     * @param oracle The oracle address.
     */
    function setOracle(address token, address oracle) external;

    /**
     * @notice Sets the pair-specific maximum conversion discount.
     * @param tokenIn The redemption token.
     * @param tokenOut The collateral token.
     * @param newPairMaxDiscount The new pair-specific maximum discount in ppm.
     */
    function setPairMaxDiscount(address tokenIn, address tokenOut, uint256 newPairMaxDiscount) external;

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
     * @param recipient Recipient of the collateral output.
     * @param amountIn Token-to-redeem amount consumed by the swap.
     * @param amountOut Collateral amount requested from the vault.
     */
    function swap(
        DiscountSwap calldata discountSwap,
        bytes calldata protocolSignature,
        address recipient,
        uint256 amountIn,
        uint256 amountOut
    ) external;
}

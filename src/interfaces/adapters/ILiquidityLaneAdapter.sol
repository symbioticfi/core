// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

uint256 constant LIQUIDITY_LANE_DISCOUNT_PRECISION = 1e6;
uint256 constant LIQUIDITY_LANE_MAX_TOKENS = 15;

bytes32 constant LIQUIDITY_LANE_SIGNED_SWAP_TYPEHASH = keccak256(
    "SignedSwap(address recipient,address tokenIn,uint256 amountIn,uint256 amountOut,address caller,address signer,uint256 nonce,uint48 deadline)"
);

/**
 * @title ILiquidityLaneAdapter
 * @notice Interface for issuer-facing instant redemption liquidity lanes.
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
     * @notice Raised when a signed swap is expired.
     */
    error ExpiredSwap();

    /**
     * @notice Raised when the delegator cannot allocate enough assets for a swap.
     */
    error InsufficientAllocation();

    /**
     * @notice Raised when a swap signer is not authorized.
     */
    error InvalidAccount();

    /**
     * @notice Raised when a signed swap is submitted by an unexpected caller.
     */
    error InvalidCaller();

    /**
     * @notice Raised when a discount exceeds precision.
     */
    error InvalidDiscount();

    /**
     * @notice Raised when a lane limit is lower than current outstanding allocation.
     */
    error InvalidLimit();

    /**
     * @notice Raised when an oracle is missing or returns zero.
     */
    error InvalidOracle();

    /**
     * @notice Raised when a swap asks for too much output.
     */
    error InvalidRate();

    /**
     * @notice Raised when token-to-redeem configuration is invalid.
     */
    error InvalidTokenToRedeem();

    /**
     * @notice Raised when swaps are paused.
     */
    error Paused();

    /**
     * @notice Raised when an unconfigured token is used.
     */
    error UnsupportedToken();

    /* STRUCTS */

    /**
     * @notice Authorized swap payload.
     * @param recipient Recipient of the vault asset output.
     * @param tokenIn Token-to-redeem consumed by the swap.
     * @param amountIn Token-to-redeem amount consumed by the swap.
     * @param amountOut Vault asset amount paid to the recipient.
     */
    struct Swap {
        address recipient;
        address tokenIn;
        uint256 amountIn;
        uint256 amountOut;
    }

    /**
     * @notice Delegated swap payload signed by an authorized signer.
     * @param recipient Recipient of the vault asset output.
     * @param tokenIn Token-to-redeem consumed by the swap.
     * @param amountIn Token-to-redeem amount consumed by the swap.
     * @param amountOut Vault asset amount paid to the recipient.
     * @param caller Caller authorized to submit the swap.
     * @param signer Authorized market maker, filler, or curator.
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

    /* EVENTS */

    /**
     * @notice Emitted when a token-to-redeem account is set.
     * @param tokenToRedeem Token consumed by swaps.
     * @param account Account that redeems the token.
     */
    event SetAccount(address indexed tokenToRedeem, address indexed account);

    /**
     * @notice Emitted when a token oracle is set.
     * @param token Priced token.
     * @param oracle Oracle address.
     */
    event SetOracle(address indexed token, address indexed oracle);

    /**
     * @notice Emitted when a redemption-token converter is set.
     * @param redemptionToken Redemption token.
     * @param converter Converter address.
     */
    event SetConverter(address indexed redemptionToken, address indexed converter);

    /**
     * @notice Emitted when the default maximum conversion discount is set.
     * @param discount New default maximum conversion discount in ppm.
     */
    event SetGlobalMaxConvertDiscount(uint256 discount);

    /**
     * @notice Emitted when a pair-specific maximum conversion discount is set.
     * @param tokenIn Input token.
     * @param tokenOut Output token.
     * @param discount New pair-specific maximum conversion discount in ppm.
     */
    event SetPairMaxConvertDiscount(address indexed tokenIn, address indexed tokenOut, uint256 discount);

    /**
     * @notice Emitted when a token lane limit is set.
     * @param tokenToRedeem Token consumed by swaps.
     * @param limit New vault-funded output limit.
     */
    event SetLimit(address indexed tokenToRedeem, uint256 limit);

    /**
     * @notice Emitted when a token lane minimum discount is set.
     * @param tokenToRedeem Token consumed by swaps.
     * @param discount New minimum discount in ppm.
     */
    event SetMinDiscount(address indexed tokenToRedeem, uint256 discount);

    /**
     * @notice Emitted when the market maker is updated.
     * @param marketMaker New market maker.
     * @param canAcquire Whether market-maker prefunding is enabled.
     */
    event SetMarketMaker(address indexed marketMaker, bool canAcquire);

    /**
     * @notice Emitted when filler authorization is updated.
     * @param marketMaker Market maker that owns the filler set.
     * @param filler Filler account.
     * @param isAuthorized Whether the filler is authorized.
     */
    event SetFiller(address indexed marketMaker, address indexed filler, bool isAuthorized);

    /**
     * @notice Emitted when swap pause status is updated.
     * @param isPaused Whether swaps are paused.
     */
    event SetPauseStatus(bool isPaused);

    /**
     * @notice Emitted when acquisition collateral is deposited.
     * @param account Account credited with acquisition balance.
     * @param tokenToRedeem Token lane funded.
     * @param amount Vault asset amount deposited.
     */
    event DepositToAcquire(address indexed account, address indexed tokenToRedeem, uint256 amount);

    /**
     * @notice Emitted when acquisition collateral is withdrawn.
     * @param account Account debited.
     * @param tokenToRedeem Token lane debited.
     * @param amount Vault asset amount withdrawn.
     */
    event WithdrawToAcquire(address indexed account, address indexed tokenToRedeem, uint256 amount);

    /**
     * @notice Emitted when a swap is executed.
     * @param swap Executed swap payload.
     * @param allocated Vault-funded output amount.
     * @param acquired Prefunded output amount.
     */
    event DoSwap(Swap swap, uint256 allocated, uint256 acquired);

    /**
     * @notice Emitted when redemption proceeds are synchronized.
     * @param principal Principal pulled from accounts.
     * @param rewards Excess rewards pulled from accounts.
     */
    event Sync(uint256 principal, uint256 rewards);

    /**
     * @notice Emitted when redemption proceeds are sent through a converter.
     * @param tokenToRedeem Token lane whose account converts proceeds.
     * @param redemptionToken Token held by the account.
     * @param amount Amount of redemption token converted.
     */
    event ConvertRedemption(address indexed tokenToRedeem, address indexed redemptionToken, uint256 amount);

    /**
     * @notice Emitted when a signed-swap nonce is invalidated.
     * @param tokenToRedeem Token lane.
     * @param nonce Invalidated nonce.
     */
    event InvalidateNonce(address indexed tokenToRedeem, uint256 indexed nonce);

    /* FUNCTIONS */

    /**
     * @notice Returns whether swaps are paused.
     * @return status Whether swaps are paused.
     */
    function isPaused() external view returns (bool status);

    /**
     * @notice Returns the configured market maker.
     * @return marketMaker Market maker address.
     */
    function marketMaker() external view returns (address marketMaker);

    /**
     * @notice Returns whether the market maker may prefund acquisition balances.
     * @return canAcquire Whether market-maker prefunding is enabled.
     */
    function marketMakerCanAcquire() external view returns (bool canAcquire);

    /**
     * @notice Returns the total outstanding vault-funded amount across lanes.
     * @return amount Outstanding amount.
     */
    function allocatedTotal() external view returns (uint256 amount);

    /**
     * @notice Returns total prefunded acquisition balance.
     * @return amount Prefunded vault asset amount.
     */
    function acquireTotal() external view returns (uint256 amount);

    /**
     * @notice Returns a token-to-redeem by index.
     * @param index Token index.
     * @return tokenToRedeem Token address.
     */
    function tokensToRedeem(uint256 index) external view returns (address tokenToRedeem);

    /**
     * @notice Returns the number of configured token lanes.
     * @return length Number of token lanes.
     */
    function tokensToRedeemLength() external view returns (uint256 length);

    /**
     * @notice Returns the redemption account for a token lane.
     * @param tokenToRedeem Token lane.
     * @return account Redemption account.
     */
    function accountOf(address tokenToRedeem) external view returns (address account);

    /**
     * @notice Returns the oracle for a token.
     * @param token Token address.
     * @return oracle Oracle address.
     */
    function oracleOf(address token) external view returns (address oracle);

    /**
     * @notice Returns the converter used for a redemption token.
     * @param redemptionToken Redemption token.
     * @return converter Converter address.
     */
    function converterOf(address redemptionToken) external view returns (address converter);

    /**
     * @notice Returns the default maximum conversion discount in ppm.
     * @return discount Discount in ppm.
     */
    function globalMaxConvertDiscount() external view returns (uint256 discount);

    /**
     * @notice Returns the pair-specific maximum conversion discount in ppm.
     * @param tokenIn Input token.
     * @param tokenOut Output token.
     * @return discount Discount in ppm.
     */
    function pairMaxConvertDiscount(address tokenIn, address tokenOut) external view returns (uint256 discount);

    /**
     * @notice Returns the vault-funded output limit for a token lane.
     * @param tokenToRedeem Token lane.
     * @return amount Limit amount.
     */
    function limit(address tokenToRedeem) external view returns (uint256 amount);

    /**
     * @notice Returns outstanding vault-funded output for a token lane.
     * @param tokenToRedeem Token lane.
     * @return amount Outstanding amount.
     */
    function allocated(address tokenToRedeem) external view returns (uint256 amount);

    /**
     * @notice Returns minimum discount in ppm for a token lane.
     * @param tokenToRedeem Token lane.
     * @return discount Discount in ppm.
     */
    function minDiscount(address tokenToRedeem) external view returns (uint256 discount);

    /**
     * @notice Returns curator-prefunded acquisition balance for a token lane.
     * @param tokenToRedeem Token lane.
     * @return amount Balance amount.
     */
    function curatorAcquireBalance(address tokenToRedeem) external view returns (uint256 amount);

    /**
     * @notice Returns market-maker-prefunded acquisition balance for a token lane.
     * @param tokenToRedeem Token lane.
     * @return amount Balance amount.
     */
    function marketMakerAcquireBalance(address tokenToRedeem) external view returns (uint256 amount);

    /**
     * @notice Returns whether an account is a filler for the market maker.
     * @param filler Filler account.
     * @return status Whether the filler is authorized.
     */
    function isFiller(address filler) external view returns (bool status);

    /**
     * @notice Returns whether a nonce is used for a token lane.
     * @param tokenToRedeem Token lane.
     * @param nonce Nonce to query.
     * @return used Whether the nonce is used.
     */
    function isUsedNonce(address tokenToRedeem, uint256 nonce) external view returns (bool used);

    /**
     * @notice Returns the maximum output currently available for a token lane.
     * @param tokenToRedeem Token lane.
     * @return amount Maximum vault asset output.
     */
    function getMaxAssets(address tokenToRedeem) external view returns (uint256 amount);

    /**
     * @notice Returns the maximum oracle-backed rate after configured discount.
     * @param tokenToRedeem Token lane.
     * @return rate Maximum 1e18-scaled rate.
     */
    function getMaxRate(address tokenToRedeem) external view returns (uint256 rate);

    /**
     * @notice Returns oracle-derived output amount.
     * @param tokenIn Input token.
     * @param tokenOut Output token.
     * @param amountIn Input amount.
     * @return amountOut Output amount.
     */
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut);

    /**
     * @notice Sets the account used by a token lane.
     * @param tokenToRedeem Token lane.
     * @param account Redemption account.
     */
    function setAccount(address tokenToRedeem, address account) external;

    /**
     * @notice Sets an oracle for a token.
     * @param token Token address.
     * @param oracle Oracle address.
     */
    function setOracle(address token, address oracle) external;

    /**
     * @notice Sets a redemption-token converter.
     * @param redemptionToken Redemption token.
     * @param converter Converter address.
     */
    function setConverter(address redemptionToken, address converter) external;

    /**
     * @notice Sets the global maximum conversion discount.
     * @param newGlobalMaxConvertDiscount New maximum conversion discount in ppm.
     */
    function setGlobalMaxConvertDiscount(uint256 newGlobalMaxConvertDiscount) external;

    /**
     * @notice Sets a pair-specific maximum conversion discount.
     * @param tokenIn Input token.
     * @param tokenOut Output token.
     * @param newPairMaxConvertDiscount New maximum conversion discount in ppm.
     */
    function setPairMaxConvertDiscount(address tokenIn, address tokenOut, uint256 newPairMaxConvertDiscount) external;

    /**
     * @notice Sets a token lane vault-funded output limit.
     * @param tokenToRedeem Token lane.
     * @param newLimit New limit.
     */
    function setLimit(address tokenToRedeem, uint256 newLimit) external;

    /**
     * @notice Sets a token lane minimum swap discount.
     * @param tokenToRedeem Token lane.
     * @param newMinDiscount New minimum discount in ppm.
     */
    function setMinDiscount(address tokenToRedeem, uint256 newMinDiscount) external;

    /**
     * @notice Sets the market maker and whether it can prefund acquisition balances.
     * @param newMarketMaker New market maker.
     * @param newCanAcquire Whether market-maker prefunding is enabled.
     */
    function setMarketMaker(address newMarketMaker, bool newCanAcquire) external;

    /**
     * @notice Sets filler authorization for the configured market maker.
     * @param filler Filler account.
     * @param isAuthorized Whether the filler is authorized.
     */
    function setFiller(address filler, bool isAuthorized) external;

    /**
     * @notice Sets swap pause status.
     * @param newPauseStatus New pause status.
     */
    function setPauseStatus(bool newPauseStatus) external;

    /**
     * @notice Prefunds acquisition balances with vault assets.
     * @param tokenToRedeem Token lane.
     * @param amount Vault asset amount.
     */
    function depositToAcquire(address tokenToRedeem, uint256 amount) external;

    /**
     * @notice Withdraws prefunded acquisition balances.
     * @param tokenToRedeem Token lane.
     * @param amount Vault asset amount.
     */
    function withdrawToAcquire(address tokenToRedeem, uint256 amount) external;

    /**
     * @notice Marks a signed-swap nonce as used.
     * @param tokenToRedeem Token lane.
     * @param nonce Nonce to invalidate.
     */
    function invalidateNonce(address tokenToRedeem, uint256 nonce) external;

    /**
     * @notice Converts redemption proceeds held by a lane account into the vault asset.
     * @param tokenToRedeem Token lane.
     * @param redemptionToken Token currently held by the account.
     * @param amount Redemption-token amount.
     * @param data Converter-specific data.
     */
    function convertRedemption(address tokenToRedeem, address redemptionToken, uint256 amount, bytes calldata data)
        external;

    /**
     * @notice Executes an authorized swap.
     * @param swapPayload Swap payload.
     */
    function swap(Swap calldata swapPayload) external;

    /**
     * @notice Executes a signed authorized swap.
     * @param signedSwap Signed swap payload.
     * @param signature Signature from the authorized signer.
     */
    function swap(SignedSwap calldata signedSwap, bytes calldata signature) external;

    /**
     * @notice Pulls available principal and rewards from redemption accounts.
     * @return principal Principal pulled.
     * @return rewards Excess rewards pulled.
     */
    function sync() external returns (uint256 principal, uint256 rewards);
}

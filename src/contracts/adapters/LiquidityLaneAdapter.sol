// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {
    ILiquidityLaneAdapter,
    LIQUIDITY_LANE_DISCOUNT_PRECISION,
    LIQUIDITY_LANE_MAX_TOKENS,
    LIQUIDITY_LANE_SIGNED_SWAP_TYPEHASH
} from "../../interfaces/adapters/ILiquidityLaneAdapter.sol";
import {ILiquidityLaneAccount} from "../../interfaces/adapters/liquidity_lane_adapter/ILiquidityLaneAccount.sol";
import {ILiquidityLaneOracle} from "../../interfaces/adapters/liquidity_lane_adapter/ILiquidityLaneOracle.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title LiquidityLaneAdapter
/// @notice Vault adapter for issuer-facing instant redemptions.
contract LiquidityLaneAdapter is EIP712, Adapter, ILiquidityLaneAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* STATE VARIABLES */

    /// @inheritdoc ILiquidityLaneAdapter
    bool public isPaused;
    /// @inheritdoc ILiquidityLaneAdapter
    address public marketMaker;
    /// @inheritdoc ILiquidityLaneAdapter
    bool public marketMakerCanAcquire;
    /// @inheritdoc ILiquidityLaneAdapter
    uint256 public allocatedTotal;
    /// @inheritdoc ILiquidityLaneAdapter
    uint256 public acquireTotal;
    /// @inheritdoc ILiquidityLaneAdapter
    uint256 public globalMaxConvertDiscount;

    /// @inheritdoc ILiquidityLaneAdapter
    address[] public tokensToRedeem;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address tokenToRedeem => address account) public accountOf;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address token => address oracle) public oracleOf;
    /// @notice Converter used for redemption-token proceeds.
    mapping(address redemptionToken => address converter) public converterOf;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address tokenToRedeem => uint256 amount) public limit;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address tokenToRedeem => uint256 amount) public allocated;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address tokenToRedeem => uint256 discount) public minDiscount;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address tokenToRedeem => uint256 amount) public curatorAcquireBalance;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address tokenToRedeem => uint256 amount) public marketMakerAcquireBalance;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address tokenToRedeem => mapping(uint256 nonce => bool used)) public isUsedNonce;
    /// @notice Pair-specific maximum conversion discounts in ppm.
    mapping(address tokenIn => mapping(address tokenOut => uint256 discount)) public pairMaxConvertDiscount;

    /// @dev Tracks membership in tokensToRedeem.
    mapping(address tokenToRedeem => bool status) internal _isTokenToRedeem;
    /// @dev Filler authorization by market maker.
    mapping(address marketMaker => mapping(address filler => bool status)) internal _isFiller;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory, address curatorRegistry)
        EIP712("LiquidityLaneAdapter", "1")
        Adapter(vaultFactory, adapterFactory, curatorRegistry)
    {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function freeAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return IERC20(IERC4626(vault).asset()).balanceOf(address(this)).saturatingSub(acquireTotal);
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return freeAssets() + allocatedTotal;
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function tokensToRedeemLength() public view returns (uint256) {
        return tokensToRedeem.length;
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function isFiller(address filler) public view returns (bool) {
        return _isFiller[marketMaker][filler];
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function getMaxAssets(address tokenToRedeem) public view returns (uint256) {
        uint256 available = freeAssets() + IUniversalDelegator(IVaultV2(vault).delegator()).allocatable(address(this));
        return Math.min(limit[tokenToRedeem].saturatingSub(allocated[tokenToRedeem]), available)
            + curatorAcquireBalance[tokenToRedeem] + marketMakerAcquireBalance[tokenToRedeem];
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function getMaxRate(address tokenToRedeem) public view returns (uint256) {
        return _getOracleRate(tokenToRedeem, IERC4626(vault).asset())
            .mulDiv(LIQUIDITY_LANE_DISCOUNT_PRECISION - minDiscount[tokenToRedeem], LIQUIDITY_LANE_DISCOUNT_PRECISION);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        return amountIn.mulDiv(
            _getOracleRate(tokenIn, tokenOut) * 10 ** IERC20Metadata(tokenOut).decimals(),
            1e18 * 10 ** IERC20Metadata(tokenIn).decimals()
        );
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc ILiquidityLaneAdapter
    function swap(Swap calldata swapPayload) public nonReentrant {
        _validateSwapAccount(msg.sender);
        _swap(swapPayload);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function swap(SignedSwap calldata signedSwap, bytes calldata signature) public nonReentrant {
        _validateSwapAccount(signedSwap.signer);
        if (signedSwap.caller != msg.sender) {
            revert InvalidCaller();
        }
        if (signedSwap.deadline < block.timestamp) {
            revert ExpiredSwap();
        }
        if (isUsedNonce[signedSwap.tokenIn][signedSwap.nonce]) {
            revert AlreadyUsedNonce();
        }
        if (!SignatureChecker.isValidSignatureNow(
                signedSwap.signer, _hashTypedDataV4(_hashSignedSwap(signedSwap)), signature
            )) {
            revert InvalidAccount();
        }

        isUsedNonce[signedSwap.tokenIn][signedSwap.nonce] = true;

        _swap(
            Swap({
                recipient: signedSwap.recipient,
                tokenIn: signedSwap.tokenIn,
                amountIn: signedSwap.amountIn,
                amountOut: signedSwap.amountOut
            })
        );
    }

    /// @notice Converts redemption proceeds held by a lane account into the vault asset.
    function convertRedemption(address tokenToRedeem, address redemptionToken, uint256 amount, bytes calldata data)
        public
        nonReentrant
    {
        address account = _account(tokenToRedeem);
        address asset = IERC4626(vault).asset();
        address converter = converterOf[redemptionToken];
        if (redemptionToken == asset || converter == address(0)) {
            revert UnsupportedToken();
        }

        ILiquidityLaneAccount(account)
            .convertRedemption(
                redemptionToken, converter, amount, _getMinAmountOut(redemptionToken, asset, amount), data
            );

        emit ConvertRedemption(tokenToRedeem, redemptionToken, amount);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function sync() public nonReentrant returns (uint256 principal, uint256 rewards) {
        (principal, rewards) = _sync(type(uint256).max);
        emit Sync(principal, rewards);
    }

    /* PUBLIC FUNCTIONS (CURATOR / MARKET MAKER) */

    /// @notice Prefunds acquisition balances with vault assets.
    function depositToAcquire(address tokenToRedeem, uint256 amount) public nonReentrant {
        bool isCurator = msg.sender == owner();
        if (!isCurator && (!marketMakerCanAcquire || msg.sender != marketMaker)) {
            revert DepositNotAllowed();
        }

        IERC20(IERC4626(vault).asset()).safeTransferFrom(msg.sender, address(this), amount);
        acquireTotal += amount;

        if (isCurator) {
            curatorAcquireBalance[tokenToRedeem] += amount;
        } else {
            marketMakerAcquireBalance[tokenToRedeem] += amount;
        }

        emit DepositToAcquire(msg.sender, tokenToRedeem, amount);
    }

    /// @notice Withdraws prefunded acquisition balances.
    function withdrawToAcquire(address tokenToRedeem, uint256 amount) public nonReentrant {
        if (msg.sender == owner()) {
            curatorAcquireBalance[tokenToRedeem] -= amount;
        } else if (msg.sender == marketMaker) {
            marketMakerAcquireBalance[tokenToRedeem] -= amount;
        } else {
            revert InvalidCaller();
        }

        acquireTotal -= amount;
        IERC20(IERC4626(vault).asset()).safeTransfer(msg.sender, amount);

        emit WithdrawToAcquire(msg.sender, tokenToRedeem, amount);
    }

    /// @notice Sets filler authorization for the configured market maker.
    function setFiller(address filler, bool isAuthorized) public {
        if (msg.sender != owner() && msg.sender != marketMaker) {
            revert InvalidCaller();
        }

        _isFiller[marketMaker][filler] = isAuthorized;

        emit SetFiller(marketMaker, filler, isAuthorized);
    }

    /// @notice Marks a signed-swap nonce as used.
    function invalidateNonce(address tokenToRedeem, uint256 nonce) public {
        _validateSwapAccount(msg.sender);
        isUsedNonce[tokenToRedeem][nonce] = true;

        emit InvalidateNonce(tokenToRedeem, nonce);
    }

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @notice Sets the account used by a token lane.
    function setAccount(address tokenToRedeem, address account) public onlyOwner {
        if (tokenToRedeem == address(0) || account == address(0)) {
            revert InvalidTokenToRedeem();
        }

        accountOf[tokenToRedeem] = account;

        emit SetAccount(tokenToRedeem, account);
    }

    /// @notice Sets an oracle for a token.
    function setOracle(address token, address oracle) public onlyOwner {
        oracleOf[token] = oracle;

        emit SetOracle(token, oracle);
    }

    /// @notice Sets a redemption-token converter.
    function setConverter(address redemptionToken, address converter) public onlyOwner {
        converterOf[redemptionToken] = converter;

        emit SetConverter(redemptionToken, converter);
    }

    /// @notice Sets the global maximum conversion discount.
    function setGlobalMaxConvertDiscount(uint256 newGlobalMaxConvertDiscount) public onlyOwner {
        if (newGlobalMaxConvertDiscount > LIQUIDITY_LANE_DISCOUNT_PRECISION) {
            revert InvalidDiscount();
        }

        globalMaxConvertDiscount = newGlobalMaxConvertDiscount;

        emit SetGlobalMaxConvertDiscount(newGlobalMaxConvertDiscount);
    }

    /// @notice Sets a pair-specific maximum conversion discount.
    function setPairMaxConvertDiscount(address tokenIn, address tokenOut, uint256 newPairMaxConvertDiscount)
        public
        onlyOwner
    {
        if (newPairMaxConvertDiscount > LIQUIDITY_LANE_DISCOUNT_PRECISION) {
            revert InvalidDiscount();
        }

        pairMaxConvertDiscount[tokenIn][tokenOut] = newPairMaxConvertDiscount;

        emit SetPairMaxConvertDiscount(tokenIn, tokenOut, newPairMaxConvertDiscount);
    }

    /// @notice Sets a token lane vault-funded output limit.
    function setLimit(address tokenToRedeem, uint256 newLimit) public onlyOwner {
        if (allocated[tokenToRedeem] > newLimit) {
            revert InvalidLimit();
        }
        if (newLimit > 0) {
            if (accountOf[tokenToRedeem] == address(0)) {
                revert InvalidTokenToRedeem();
            }
            if (oracleOf[tokenToRedeem] == address(0)) {
                revert InvalidOracle();
            }
            _addTokenToRedeem(tokenToRedeem);
        } else {
            _removeTokenToRedeem(tokenToRedeem);
        }

        limit[tokenToRedeem] = newLimit;

        emit SetLimit(tokenToRedeem, newLimit);
    }

    /// @notice Sets a token lane minimum swap discount.
    function setMinDiscount(address tokenToRedeem, uint256 newMinDiscount) public onlyOwner {
        if (newMinDiscount > LIQUIDITY_LANE_DISCOUNT_PRECISION) {
            revert InvalidDiscount();
        }

        minDiscount[tokenToRedeem] = newMinDiscount;

        emit SetMinDiscount(tokenToRedeem, newMinDiscount);
    }

    /// @notice Sets the market maker and whether it can prefund acquisition balances.
    function setMarketMaker(address newMarketMaker, bool newCanAcquire) public onlyOwner {
        marketMaker = newMarketMaker;
        marketMakerCanAcquire = newCanAcquire;

        emit SetMarketMaker(newMarketMaker, newCanAcquire);
    }

    /// @notice Sets swap pause status.
    function setPauseStatus(bool newPauseStatus) public onlyOwner {
        isPaused = newPauseStatus;

        emit SetPauseStatus(newPauseStatus);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Allocates assets into this lane adapter.
    function _allocate(uint256 amount) internal pure override returns (uint256) {
        return amount;
    }

    /// @dev Deallocates available synchronized assets.
    function _deallocate(uint256 amount) internal override returns (uint256 deallocated) {
        (uint256 principal, uint256 rewards) = _sync(amount);
        deallocated = principal + rewards;
    }

    /// @dev Executes a direct or signed swap after caller authentication.
    function _swap(Swap memory swapPayload) internal {
        if (isPaused) {
            revert Paused();
        }
        _account(swapPayload.tokenIn);
        if (
            swapPayload.amountOut
                > getAmountOut(swapPayload.tokenIn, IERC4626(vault).asset(), swapPayload.amountIn)
                    .mulDiv(
                        LIQUIDITY_LANE_DISCOUNT_PRECISION - minDiscount[swapPayload.tokenIn],
                        LIQUIDITY_LANE_DISCOUNT_PRECISION
                    )
        ) {
            revert InvalidRate();
        }

        IERC20(swapPayload.tokenIn).safeTransferFrom(msg.sender, address(this), swapPayload.amountIn);

        uint256 toAcquire = Math.min(
            swapPayload.amountOut,
            curatorAcquireBalance[swapPayload.tokenIn] + marketMakerAcquireBalance[swapPayload.tokenIn]
        );
        uint256 toAllocate = swapPayload.amountOut - toAcquire;
        if (allocated[swapPayload.tokenIn] + toAllocate > limit[swapPayload.tokenIn]) {
            revert InvalidLimit();
        }

        if (toAllocate > 0) {
            uint256 toPull = toAllocate.saturatingSub(freeAssets());
            if (toPull > 0 && IUniversalDelegator(IVaultV2(vault).delegator()).allocate(address(this), toPull) < toPull)
            {
                revert InsufficientAllocation();
            }

            allocated[swapPayload.tokenIn] += toAllocate;
            allocatedTotal += toAllocate;
        }

        _settleAcquisition(swapPayload.tokenIn, swapPayload.amountIn, swapPayload.amountOut, toAcquire);

        uint256 toRedeem = swapPayload.amountOut == 0
            ? swapPayload.amountIn
            : swapPayload.amountIn - toAcquire.mulDiv(swapPayload.amountIn, swapPayload.amountOut);
        if (toRedeem > 0) {
            address account = accountOf[swapPayload.tokenIn];
            IERC20(swapPayload.tokenIn).safeTransfer(account, toRedeem);
            ILiquidityLaneAccount(account).redeem(toRedeem, toAllocate);
        }

        IERC20(IERC4626(vault).asset()).safeTransfer(swapPayload.recipient, swapPayload.amountOut);

        emit DoSwap(swapPayload, toAllocate, toAcquire);
    }

    /// @dev Sends prefund-acquired token inventory to the prefunders and debits their balances.
    function _settleAcquisition(address tokenToRedeem, uint256 amountIn, uint256 amountOut, uint256 amountToAcquire)
        internal
    {
        if (amountToAcquire == 0) {
            return;
        }

        uint256 curatorSpent = Math.min(curatorAcquireBalance[tokenToRedeem], amountToAcquire);
        uint256 marketMakerSpent = amountToAcquire - curatorSpent;
        curatorAcquireBalance[tokenToRedeem] -= curatorSpent;
        marketMakerAcquireBalance[tokenToRedeem] -= marketMakerSpent;
        acquireTotal -= amountToAcquire;

        uint256 acquired = amountToAcquire.mulDiv(amountIn, amountOut);
        uint256 curatorAcquired = curatorSpent.mulDiv(acquired, amountToAcquire);
        if (curatorAcquired > 0) {
            IERC20(tokenToRedeem).safeTransfer(owner(), curatorAcquired);
        }
        if (acquired > curatorAcquired) {
            IERC20(tokenToRedeem).safeTransfer(marketMaker, acquired - curatorAcquired);
        }
    }

    /// @dev Pulls available principal and rewards from accounts.
    function _sync(uint256 amount) internal returns (uint256 principal, uint256 rewards) {
        address asset = IERC4626(vault).asset();
        for (uint256 i; i < tokensToRedeem.length && principal < amount; ++i) {
            address tokenToRedeem = tokensToRedeem[i];
            address account = accountOf[tokenToRedeem];
            if (account == address(0)) {
                continue;
            }

            (uint256 curPrincipal, uint256 curRewards) = ILiquidityLaneAccount(account).deallocate();
            if (curPrincipal > allocated[tokenToRedeem]) {
                curRewards += curPrincipal - allocated[tokenToRedeem];
                curPrincipal = allocated[tokenToRedeem];
            }
            if (curPrincipal == 0 && curRewards == 0) {
                continue;
            }

            allocated[tokenToRedeem] -= curPrincipal;
            allocatedTotal -= curPrincipal;
            principal += curPrincipal;
            rewards += curRewards;

            IERC20(asset).safeTransferFrom(account, address(this), curPrincipal + curRewards);
        }
    }

    /// @dev Returns the minimum acceptable output for redemption-proceeds conversion.
    function _getMinAmountOut(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        uint256 maxDiscount = pairMaxConvertDiscount[tokenIn][tokenOut];
        if (maxDiscount == 0) {
            maxDiscount = globalMaxConvertDiscount;
        }
        return getAmountOut(tokenIn, tokenOut, amountIn)
            .mulDiv(LIQUIDITY_LANE_DISCOUNT_PRECISION - maxDiscount, LIQUIDITY_LANE_DISCOUNT_PRECISION);
    }

    /// @dev Hashes a signed swap payload for EIP-712 signing.
    function _hashSignedSwap(SignedSwap calldata signedSwap) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                LIQUIDITY_LANE_SIGNED_SWAP_TYPEHASH,
                signedSwap.recipient,
                signedSwap.tokenIn,
                signedSwap.amountIn,
                signedSwap.amountOut,
                signedSwap.caller,
                signedSwap.signer,
                signedSwap.nonce,
                signedSwap.deadline
            )
        );
    }

    /// @dev Returns the oracle-derived rate between two tokens.
    function _getOracleRate(address tokenIn, address tokenOut) internal view returns (uint256) {
        return _getOraclePrice(tokenIn).mulDiv(1e18, _getOraclePrice(tokenOut));
    }

    /// @dev Returns a configured oracle price.
    function _getOraclePrice(address token) internal view returns (uint256 price) {
        address oracle = oracleOf[token];
        if (oracle == address(0)) {
            revert InvalidOracle();
        }
        price = ILiquidityLaneOracle(oracle).getPrice();
        if (price == 0) {
            revert InvalidOracle();
        }
    }

    /// @dev Returns a configured account or reverts.
    function _account(address tokenToRedeem) internal view returns (address account) {
        account = accountOf[tokenToRedeem];
        if (account == address(0)) {
            revert UnsupportedToken();
        }
    }

    /// @dev Reverts if an account is not authorized to execute swaps.
    function _validateSwapAccount(address account) internal view {
        if (account != owner() && account != marketMaker && !isFiller(account)) {
            revert InvalidAccount();
        }
    }

    /// @dev Adds a token lane to the enumerable list.
    function _addTokenToRedeem(address tokenToRedeem) internal {
        if (_isTokenToRedeem[tokenToRedeem]) {
            return;
        }
        if (tokensToRedeem.length == LIQUIDITY_LANE_MAX_TOKENS) {
            revert InvalidLimit();
        }

        _isTokenToRedeem[tokenToRedeem] = true;
        tokensToRedeem.push(tokenToRedeem);
    }

    /// @dev Removes a token lane from the enumerable list.
    function _removeTokenToRedeem(address tokenToRedeem) internal {
        if (!_isTokenToRedeem[tokenToRedeem]) {
            return;
        }

        uint256 length = tokensToRedeem.length;
        for (uint256 i; i < length; ++i) {
            if (tokensToRedeem[i] == tokenToRedeem) {
                tokensToRedeem[i] = tokensToRedeem[length - 1];
                tokensToRedeem.pop();
                _isTokenToRedeem[tokenToRedeem] = false;
                return;
            }
        }
    }
}

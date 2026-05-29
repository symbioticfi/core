// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {
    DISCOUNT_SWAP_TYPEHASH,
    DISCOUNT_TYPEHASH,
    DISCOUNT_PRECISION,
    ILiquidityLaneAdapter,
    MAX_TOKENS_TO_REDEEM,
    SIGNED_SWAP_TYPEHASH
} from "../../interfaces/adapters/ILiquidityLaneAdapter.sol";
import {
    ILiquidityLaneAccount as IAccount
} from "../../interfaces/adapters/liquidity_lane_adapter/ILiquidityLaneAccount.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {
    ILiquidityLaneOracle as IOracle
} from "../../interfaces/adapters/liquidity_lane_adapter/ILiquidityLaneOracle.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title LiquidityLaneAdapter
/// @notice Vault adapter for issuer-facing instant redemptions backed by deterministic redemption accounts.
contract LiquidityLaneAdapter is EIP712, Adapter, ILiquidityLaneAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* STATE VARIABLES */

    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address vault => bool) public isPaused;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address vault => address) public marketMaker;
    /// @notice Tokens-to-redeem configured for a vault.
    mapping(address vault => address[]) public tokensToRedeem;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address vault => bool) public marketMakerCanAcquire;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address vault => mapping(address tokenToRedeem => uint256 amount)) public limit;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address vault => mapping(address tokenToRedeem => uint256 ppm)) public minDiscount;
    /// @notice Vault-funded collateral currently outstanding per token-to-redeem.
    mapping(address vault => mapping(address tokenToRedeem => uint256 amount)) public allocated;

    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address vault => mapping(address tokenToRedeem => uint256 amount)) public curatorAcquireBalance;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address vault => mapping(address tokenToRedeem => mapping(address marketMaker => uint256 amount))) public
        marketMakerAcquireBalances;
    /// @notice Total acquisition collateral deposited for a vault.
    mapping(address vault => uint256 amount) public acquireTotal;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address who => address) public receiver;

    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address marketMaker => mapping(address filler => bool)) public isFiller;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address vault => mapping(address tokenToRedeem => mapping(uint256 nonce => bool))) public isUsedNonce;

    /// @inheritdoc ILiquidityLaneAdapter
    uint256 public globalMaxConvertDiscount;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address tokenToRedeem => address beacon) public accountBeacons;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address token => address oracle) public oracles;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address redemptionToken => mapping(address collateralToken => address converter)) public converters;
    /// @inheritdoc ILiquidityLaneAdapter
    mapping(address tokenIn => mapping(address tokenOut => uint256 ppm)) public pairMaxConvertDiscount;

    /// @dev Set while the adapter is funding a swap through VaultV2.
    bool internal _inSwap;

    /* MODIFIERS */

    modifier onlyVault(address curVault) {
        if (curVault != vault) {
            revert NotVault();
        }
        _;
    }

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory)
        EIP712("LiquidityLaneAdapter", "1")
        Adapter(vaultFactory, adapterFactory)
    {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function allocatable() public view override(Adapter, IAdapter) returns (uint256) {
        return _inSwap ? super.allocatable() : 0;
    }

    /// @notice Returns whether the current vault may allocate into this adapter.
    function allocatable(address vault_) public view onlyVault(vault_) returns (uint256) {
        return allocatable();
    }

    /// @inheritdoc IAdapter
    function freeAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return IERC20(IERC4626(vault).asset()).balanceOf(address(this)).saturatingSub(acquireTotal[vault]);
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return freeAssets() + _allocatedTotal(vault);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function getAccount(address vault, address tokenToRedeem) public view onlyVault(vault) returns (address) {
        address beacon = accountBeacons[tokenToRedeem];
        return beacon != address(0) ? _predictBeaconProxy(beacon, _accountSalt(vault, tokenToRedeem)) : address(0);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function getMaxAssets(address vault, address tokenToRedeem) public view onlyVault(vault) returns (uint256) {
        uint256 available = freeAssets();
        address delegator = IVaultV2(vault).delegator();
        if (delegator != address(0)) {
            uint256 toAllocate = IUniversalDelegator(delegator).limitOf(address(this)).saturatingSub(totalAssets());
            available += Math.min(toAllocate, IVaultV2(vault).freeAssets());
        }

        return Math.min(limit[vault][tokenToRedeem] - allocated[vault][tokenToRedeem], available)
            + curatorAcquireBalance[vault][tokenToRedeem]
            + marketMakerAcquireBalances[vault][tokenToRedeem][marketMaker[vault]];
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function getMaxRate(address vault, address tokenToRedeem) public view onlyVault(vault) returns (uint256) {
        return _getOracleRate(tokenToRedeem, IERC4626(vault).asset())
            .mulDiv(DISCOUNT_PRECISION - minDiscount[vault][tokenToRedeem], DISCOUNT_PRECISION);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        return amountIn.mulDiv(
            _getOracleRate(tokenIn, tokenOut) * 10 ** IERC20Metadata(tokenOut).decimals(),
            1e18 * 10 ** IERC20Metadata(tokenIn).decimals()
        );
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function getTokensToRedeemLength(address vault) public view onlyVault(vault) returns (uint256) {
        return tokensToRedeem[vault].length;
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc ILiquidityLaneAdapter
    function convertRedemption(
        address vault,
        address tokenToRedeem,
        address redemptionToken,
        uint256 redemptionAmount,
        bytes calldata data
    ) public onlyVault(vault) {
        if (tokenToRedeem == address(0)) {
            revert InvalidTokenToRedeem();
        }
        address collateral = IERC4626(vault).asset();
        if (redemptionToken == collateral) {
            revert InvalidRedemptionToken();
        }
        uint256 maxDiscount = pairMaxConvertDiscount[redemptionToken][collateral];
        if (maxDiscount == 0) {
            maxDiscount = globalMaxConvertDiscount;
        }
        uint256 minAmountOut = getAmountOut(redemptionToken, collateral, redemptionAmount)
            .mulDiv(DISCOUNT_PRECISION - maxDiscount, DISCOUNT_PRECISION);
        IAccount(_deployAccount(vault, tokenToRedeem))
            .convertRedemption(
                redemptionToken, converters[redemptionToken][collateral], redemptionAmount, minAmountOut, data
            );

        emit ConvertRedemption(vault, tokenToRedeem, redemptionToken, redemptionAmount);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setReceiver(address newReceiver) public {
        if (newReceiver == address(0)) {
            revert InvalidReceiver();
        }

        receiver[msg.sender] = newReceiver;

        emit SetReceiver(msg.sender, newReceiver);
    }

    /* PUBLIC FUNCTIONS (MARKET MAKER) */

    /// @inheritdoc ILiquidityLaneAdapter
    function swap(Swap calldata swapPayload) public onlyVault(swapPayload.vault) {
        _validateSwapAccount(swapPayload.vault, msg.sender);
        _swap(swapPayload);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function swap(SignedSwap calldata signedSwap, bytes calldata signature) public onlyVault(signedSwap.vault) {
        _validateSwapAccount(signedSwap.vault, signedSwap.signer);
        if (signedSwap.caller != msg.sender) {
            revert InvalidCaller();
        }
        if (signedSwap.deadline < block.timestamp) {
            revert ExpiredSwap();
        }
        if (isUsedNonce[signedSwap.vault][signedSwap.tokenIn][signedSwap.nonce]) {
            revert AlreadyUsedNonce();
        }
        if (!SignatureChecker.isValidSignatureNow(
                signedSwap.signer, _hashTypedDataV4(keccak256(abi.encode(SIGNED_SWAP_TYPEHASH, signedSwap))), signature
            )) {
            revert InvalidSignature();
        }

        isUsedNonce[signedSwap.vault][signedSwap.tokenIn][signedSwap.nonce] = true;

        _swap(
            Swap({
                recipient: signedSwap.recipient,
                vault: signedSwap.vault,
                tokenIn: signedSwap.tokenIn,
                amountIn: signedSwap.amountIn,
                amountOut: signedSwap.amountOut
            })
        );
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function swap(
        DiscountSwap calldata discountSwap,
        bytes calldata protocolSignature,
        address recipient,
        uint256 amountIn,
        uint256 amountOut
    ) public onlyVault(discountSwap.discount.vault) {
        Discount calldata discount = discountSwap.discount;
        _validateSwapAccount(discount.vault, discount.signer);
        if (discount.deadline < block.timestamp || discountSwap.protocolDeadline < block.timestamp) {
            revert ExpiredSwap();
        }
        if (isUsedNonce[discount.vault][discount.tokenToRedeem][discount.nonce]) {
            revert AlreadyUsedNonce();
        }
        if (
            discount.discount < minDiscount[discount.vault][discount.tokenToRedeem]
                || discount.discount > DISCOUNT_PRECISION
        ) {
            revert InvalidDiscount();
        }
        if (!SignatureChecker.isValidSignatureNow(
                discount.signer, _hashTypedDataV4(_hashDiscount(discount)), discountSwap.signerSignature
            )) {
            revert InvalidSignature();
        }
        if (!SignatureChecker.isValidSignatureNow(
                discount.protocol, _hashTypedDataV4(_hashDiscountSwap(discountSwap)), protocolSignature
            )) {
            revert InvalidSignature();
        }

        uint256 maxAmountOut = getAmountOut(discount.tokenToRedeem, IERC4626(discount.vault).asset(), amountIn)
            .mulDiv(DISCOUNT_PRECISION - discount.discount, DISCOUNT_PRECISION);
        if (amountOut > maxAmountOut) {
            revert InvalidSwapRate();
        }

        isUsedNonce[discount.vault][discount.tokenToRedeem][discount.nonce] = true;

        _swap(
            Swap({
                recipient: recipient,
                vault: discount.vault,
                tokenIn: discount.tokenToRedeem,
                amountIn: amountIn,
                amountOut: amountOut
            })
        );
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setFiller(address vault, address filler, bool isAuthorized) public onlyVault(vault) {
        address curMarketMaker = marketMaker[vault];
        if (owner() != msg.sender && curMarketMaker != msg.sender) {
            revert InvalidCaller();
        }

        isFiller[curMarketMaker][filler] = isAuthorized;

        emit SetFiller(vault, curMarketMaker, filler, isAuthorized);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function invalidateNonce(address vault, address tokenToRedeem, uint256 nonce) public onlyVault(vault) {
        address curMarketMaker = marketMaker[vault];
        if (owner() != msg.sender && curMarketMaker != msg.sender && !isFiller[curMarketMaker][msg.sender]) {
            revert InvalidCaller();
        }

        isUsedNonce[vault][tokenToRedeem][nonce] = true;

        emit InvalidateNonce(vault, tokenToRedeem, nonce);
    }

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc ILiquidityLaneAdapter
    function depositToAcquire(address vault, address tokenToRedeem, uint256 amount) public onlyVault(vault) {
        bool isOwner = owner() == msg.sender;
        address curMarketMaker = marketMaker[vault];
        if (!isOwner && (!marketMakerCanAcquire[vault] || curMarketMaker != msg.sender)) {
            revert DepositNotAllowed();
        }
        if (receiver[msg.sender] == address(0)) {
            revert InvalidReceiver();
        }

        IERC20(IERC4626(vault).asset()).safeTransferFrom(msg.sender, address(this), amount);
        acquireTotal[vault] += amount;

        if (isOwner) {
            curatorAcquireBalance[vault][tokenToRedeem] += amount;
        } else {
            marketMakerAcquireBalances[vault][tokenToRedeem][curMarketMaker] += amount;
        }

        emit DepositToAcquire(vault, tokenToRedeem, amount);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function withdrawToAcquire(address vault, address tokenToRedeem, uint256 amount) public onlyVault(vault) {
        if (owner() == msg.sender) {
            curatorAcquireBalance[vault][tokenToRedeem] -= amount;
        } else {
            marketMakerAcquireBalances[vault][tokenToRedeem][msg.sender] -= amount;
        }
        acquireTotal[vault] -= amount;
        IERC20(IERC4626(vault).asset()).safeTransfer(msg.sender, amount);

        emit WithdrawToAcquire(vault, tokenToRedeem, amount);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setMakerMaker(address vault, address newMarketMaker, bool newCanAcquire)
        public
        onlyVault(vault)
        onlyOwner
    {
        marketMaker[vault] = newMarketMaker;
        marketMakerCanAcquire[vault] = newCanAcquire;

        emit SetMarketMaker(vault, newMarketMaker, newCanAcquire);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setLimit(address vault, address tokenToRedeem, uint256 newLimit) public onlyVault(vault) onlyOwner {
        unchecked {
            if (allocated[vault][tokenToRedeem] > newLimit) {
                revert InvalidLimit();
            }

            mapping(address => uint256) storage vaultLimit = limit[vault];
            address[] storage vaultTokensToRedeem = tokensToRedeem[vault];

            uint256 numATokensToRedeem = vaultTokensToRedeem.length;
            if (newLimit > 0) {
                if (vaultLimit[tokenToRedeem] == 0) {
                    if (numATokensToRedeem >= MAX_TOKENS_TO_REDEEM) {
                        revert InvalidLimit();
                    }
                    if (oracles[tokenToRedeem] == address(0)) {
                        revert InvalidOracle();
                    }
                    vaultTokensToRedeem.push(tokenToRedeem);
                }
            } else {
                for (uint256 i; i < numATokensToRedeem; ++i) {
                    if (tokenToRedeem == vaultTokensToRedeem[i]) {
                        vaultTokensToRedeem[i] = vaultTokensToRedeem[numATokensToRedeem - 1];
                        vaultTokensToRedeem.pop();
                        break;
                    }
                }
            }
            vaultLimit[tokenToRedeem] = newLimit;

            emit SetLimit(vault, tokenToRedeem, newLimit);
        }
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setMinDiscount(address vault, address tokenToRedeem, uint256 newMinDiscount)
        public
        onlyVault(vault)
        onlyOwner
    {
        if (newMinDiscount > DISCOUNT_PRECISION) {
            revert InvalidDiscount();
        }

        minDiscount[vault][tokenToRedeem] = newMinDiscount;

        emit SetMinDiscount(vault, tokenToRedeem, newMinDiscount);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setPauseStatus(address vault, bool newPauseStatus) public onlyVault(vault) onlyOwner {
        isPaused[vault] = newPauseStatus;

        emit SetPauseStatus(vault, newPauseStatus);
    }

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc ILiquidityLaneAdapter
    function setAccountBeacon(address tokenToRedeem, address beacon) public onlyOwner {
        accountBeacons[tokenToRedeem] = beacon;

        emit SetAccountBeacon(tokenToRedeem, beacon);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setConversionAdapter(address redemptionToken, address collateralToken, address conversionAdapter)
        public
        onlyOwner
    {
        converters[redemptionToken][collateralToken] = conversionAdapter;

        emit SetConversionAdapter(redemptionToken, collateralToken, conversionAdapter);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setGlobalMaxDiscount(uint256 newGlobalMaxDiscount) public onlyOwner {
        if (newGlobalMaxDiscount > DISCOUNT_PRECISION) {
            revert InvalidDiscount();
        }

        globalMaxConvertDiscount = newGlobalMaxDiscount;

        emit SetGlobalMaxDiscount(newGlobalMaxDiscount);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setOracle(address token, address oracle) public onlyOwner {
        oracles[token] = oracle;

        emit SetOracle(token, oracle);
    }

    /// @inheritdoc ILiquidityLaneAdapter
    function setPairMaxDiscount(address tokenIn, address tokenOut, uint256 newPairMaxDiscount) public onlyOwner {
        if (newPairMaxDiscount > DISCOUNT_PRECISION) {
            revert InvalidDiscount();
        }

        pairMaxConvertDiscount[tokenIn][tokenOut] = newPairMaxDiscount;

        emit SetPairMaxDiscount(tokenIn, tokenOut, newPairMaxDiscount);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the deterministic account salt for a `(vault, tokenToRedeem)` pair.
    /// @param vault The vault address.
    /// @param tokenToRedeem The token-to-redeem address.
    /// @return salt The deterministic deployment salt.
    function _accountSalt(address vault, address tokenToRedeem) internal pure returns (bytes32) {
        return keccak256(abi.encode(vault, tokenToRedeem));
    }

    /// @dev Returns the init code hash for a beacon proxy with empty initialization data.
    /// @param beacon The beacon address used by the proxy.
    /// @return initCodeHash The deterministic proxy init code hash.
    function _beaconProxyBytecodeHash(address beacon) internal pure returns (bytes32 initCodeHash) {
        return keccak256(abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(beacon, bytes(""))));
    }

    /// @dev Returns the deterministic beacon proxy address for `salt`.
    /// @param beacon The beacon address used by the proxy.
    /// @param salt The deterministic deployment salt.
    /// @return account The predicted proxy address.
    function _predictBeaconProxy(address beacon, bytes32 salt) internal view returns (address account) {
        return Create2.computeAddress(salt, _beaconProxyBytecodeHash(beacon), address(this));
    }

    /// @dev Deploys a deterministic beacon proxy with empty initialization data.
    /// @param beacon The beacon address used by the proxy.
    /// @param salt The deterministic deployment salt.
    /// @return account The deployed proxy address.
    function _deployBeaconProxy(address beacon, bytes32 salt) internal returns (address account) {
        return address(new BeaconProxy{salt: salt}(beacon, ""));
    }

    /// @dev Returns the oracle-derived exchange rate from `tokenToRate` into `baseToken`.
    /// @param tokenToRate The token being priced.
    /// @param baseToken The quote token.
    /// @return rate The 1e18-scaled exchange rate.
    function _getOracleRate(address tokenToRate, address baseToken) internal view returns (uint256) {
        return _getOraclePrice(tokenToRate).mulDiv(1e18, _getOraclePrice(baseToken));
    }

    /// @dev Returns the minimum acceptable collateral output for a conversion.
    /// @param redemptionToken The token being converted.
    /// @param collateral The vault collateral token.
    /// @param redemptionAmount The redemption-token amount being converted.
    /// @return minAmountOut The minimum acceptable collateral amount.
    function _getMinAmountOut(address redemptionToken, address collateral, uint256 redemptionAmount)
        internal
        view
        returns (uint256)
    {
        uint256 maxDiscount = pairMaxConvertDiscount[redemptionToken][collateral];
        if (maxDiscount == 0) {
            maxDiscount = globalMaxConvertDiscount;
        }

        return getAmountOut(redemptionToken, collateral, redemptionAmount)
            .mulDiv(DISCOUNT_PRECISION - maxDiscount, DISCOUNT_PRECISION);
    }

    /// @dev Returns the configured oracle price for a token.
    /// @param token The token being priced.
    /// @return price The token price in 1e18 precision.
    function _getOraclePrice(address token) internal view returns (uint256 price) {
        address oracle = oracles[token];
        if (oracle == address(0)) {
            revert InvalidOracle();
        }
        price = IOracle(oracle).getPrice();
        if (price == 0) {
            revert InvalidOracle();
        }
    }

    /// @dev Reverts if `account` is not authorized to swap for `vault`.
    /// @param vault The vault address.
    /// @param account The account being validated.
    function _validateSwapAccount(address vault, address account) internal view {
        address curMarketMaker = marketMaker[vault];
        if (account != owner() && account != curMarketMaker && !isFiller[curMarketMaker][account]) {
            revert InvalidAccount();
        }
    }

    /// @dev Hashes a discount payload for EIP-712 signing.
    /// @param discount The discount payload.
    /// @return digest The struct hash.
    function _hashDiscount(Discount calldata discount) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DISCOUNT_TYPEHASH,
                discount.vault,
                discount.tokenToRedeem,
                discount.discount,
                discount.signer,
                discount.protocol,
                discount.nonce,
                discount.deadline
            )
        );
    }

    /// @dev Hashes a protocol-wrapped discount swap payload for EIP-712 signing.
    /// @param discountSwap The wrapped discount swap payload.
    /// @return digest The struct hash.
    function _hashDiscountSwap(DiscountSwap calldata discountSwap) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DISCOUNT_SWAP_TYPEHASH,
                _hashDiscount(discountSwap.discount),
                keccak256(discountSwap.signerSignature),
                discountSwap.protocolDeadline
            )
        );
    }

    /// @dev Triggers adapter allocation through the current delegator.
    /// @param amount The collateral amount requested by the vault.
    function _allocate(uint256 amount) internal pure override returns (uint256) {
        return amount;
    }

    /// @dev Pulls all available collateral from redemption accounts for the calling vault.
    /// @return deallocated The collateral returned from redemption accounts.
    function _deallocate(uint256) internal override returns (uint256 deallocated) {
        address collateral = IERC4626(vault).asset();
        address[] storage vaultTokensToRedeem = tokensToRedeem[vault];
        for (uint256 i; i < getTokensToRedeemLength(vault); ++i) {
            address tokenToRedeem = vaultTokensToRedeem[i];
            address account = getAccount(vault, tokenToRedeem);
            if (account.code.length == 0) {
                continue;
            }
            (uint256 principal, uint256 rewards) = IAccount(account).deallocate();
            allocated[vault][tokenToRedeem] -= principal;
            IERC20(collateral).safeTransferFrom(account, address(this), principal + rewards);
            deallocated += principal + rewards;
        }
    }

    /// @dev Executes a direct or delegated swap after caller authentication has already succeeded.
    /// @param swapPayload The swap payload to execute.
    function _swap(Swap memory swapPayload) internal {
        if (isPaused[swapPayload.vault]) {
            revert Paused();
        }
        if (
            swapPayload.amountOut
                > getAmountOut(swapPayload.tokenIn, IERC4626(swapPayload.vault).asset(), swapPayload.amountIn)
                    .mulDiv(
                        DISCOUNT_PRECISION - minDiscount[swapPayload.vault][swapPayload.tokenIn], DISCOUNT_PRECISION
                    )
        ) {
            revert InvalidSwapRate();
        }

        address curMarketMaker = marketMaker[swapPayload.vault];
        uint256 curCuratorAcquireBalance = curatorAcquireBalance[swapPayload.vault][swapPayload.tokenIn];
        uint256 curMarketMakerAcquireBalance =
            marketMakerAcquireBalances[swapPayload.vault][swapPayload.tokenIn][curMarketMaker];
        uint256 tokenOutToAcquire =
            Math.min(swapPayload.amountOut, curCuratorAcquireBalance + curMarketMakerAcquireBalance);

        uint256 tokenOutToAllocate = swapPayload.amountOut - tokenOutToAcquire;
        uint256 curLimit = limit[swapPayload.vault][swapPayload.tokenIn];
        if (allocated[swapPayload.vault][swapPayload.tokenIn] + tokenOutToAllocate > curLimit) {
            revert InvalidCollateralOut();
        }
        allocated[swapPayload.vault][swapPayload.tokenIn] += tokenOutToAllocate;

        if (tokenOutToAllocate > 0) {
            uint256 tokenOutToPull = tokenOutToAllocate.saturatingSub(freeAssets());
            if (tokenOutToPull > 0) {
                _inSwap = true;
                uint256 pulled = IUniversalDelegator(IVaultV2(swapPayload.vault).delegator())
                    .allocate(address(this), tokenOutToPull);
                _inSwap = false;
                if (pulled < tokenOutToPull) {
                    revert InsufficientAllocation();
                }
            }
        }

        uint256 tokenInAcquired;
        if (tokenOutToAcquire > 0) {
            tokenInAcquired = tokenOutToAcquire.mulDiv(swapPayload.amountIn, swapPayload.amountOut);
            uint256 curatorAcquireBalanceSpent = (tokenOutToAcquire + 1) >> 1;
            if (curatorAcquireBalanceSpent > curCuratorAcquireBalance) {
                curatorAcquireBalanceSpent = curCuratorAcquireBalance;
            }
            uint256 marketMakerAcquireBalanceSpent = tokenOutToAcquire - curatorAcquireBalanceSpent;
            if (marketMakerAcquireBalanceSpent > curMarketMakerAcquireBalance) {
                marketMakerAcquireBalanceSpent = curMarketMakerAcquireBalance;
                curatorAcquireBalanceSpent = tokenOutToAcquire - marketMakerAcquireBalanceSpent;
            }

            curatorAcquireBalance[swapPayload.vault][swapPayload.tokenIn] =
                curCuratorAcquireBalance - curatorAcquireBalanceSpent;
            marketMakerAcquireBalances[swapPayload.vault][swapPayload.tokenIn][curMarketMaker] =
                curMarketMakerAcquireBalance - marketMakerAcquireBalanceSpent;
            acquireTotal[swapPayload.vault] -= tokenOutToAcquire;

            uint256 marketMakerAcquired = marketMakerAcquireBalanceSpent.mulDiv(tokenInAcquired, tokenOutToAcquire);
            uint256 curatorAcquired = tokenInAcquired - marketMakerAcquired;
            if (curatorAcquired > 0) {
                address curatorReceiver = receiver[owner()];
                if (curatorReceiver == address(0)) {
                    revert InvalidReceiver();
                }
                IERC20(swapPayload.tokenIn).safeTransfer(curatorReceiver, curatorAcquired);
            }
            if (marketMakerAcquired > 0) {
                address marketMakerReceiver = receiver[curMarketMaker];
                if (marketMakerReceiver == address(0)) {
                    revert InvalidReceiver();
                }
                IERC20(swapPayload.tokenIn).safeTransfer(marketMakerReceiver, marketMakerAcquired);
            }
        }

        uint256 tokenInToRedeem = swapPayload.amountIn - tokenInAcquired;
        if (tokenInToRedeem > 0) {
            address account = _deployAccount(swapPayload.vault, swapPayload.tokenIn);
            IERC20(swapPayload.tokenIn).safeTransfer(account, tokenInToRedeem);
            IAccount(account).redeem(tokenInToRedeem, tokenOutToAllocate);
        }

        IERC20(IERC4626(swapPayload.vault).asset()).safeTransfer(swapPayload.recipient, swapPayload.amountOut);

        emit DoSwap(swapPayload);
    }

    /// @dev Returns total vault-funded allocation for a vault.
    function _allocatedTotal(address vault) internal view returns (uint256 amount) {
        for (uint256 i; i < getTokensToRedeemLength(vault); ++i) {
            amount += allocated[vault][tokensToRedeem[vault][i]];
        }
    }

    /// @dev Deploys the deterministic account for a `(vault, tokenToRedeem)` pair when absent.
    /// @param vault The vault address.
    /// @param tokenToRedeem The token-to-redeem address.
    /// @return account The deployed or existing account address.
    function _deployAccount(address vault, address tokenToRedeem) internal returns (address account) {
        account = getAccount(vault, tokenToRedeem);
        if (account.code.length > 0) {
            return account;
        }
        account = _deployBeaconProxy(accountBeacons[tokenToRedeem], _accountSalt(vault, tokenToRedeem));
        IAccount(account).initialize(vault);
    }
}

// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {
    DISCOUNT_SWAP_TYPEHASH,
    DISCOUNT_TYPEHASH,
    DISCOUNT_PRECISION,
    ILiquidLaneAdapter,
    MAX_TOKENS_TO_REDEEM,
    SIGNED_SWAP_TYPEHASH
} from "../../interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAccountRegistry} from "../../interfaces/adapters/ll-adapter/IAccountRegistry.sol";
import {IAccount} from "../../interfaces/adapters/ll-adapter/IAccount.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IMigratablesFactory} from "../../interfaces/common/IMigratablesFactory.sol";
import {IOracle} from "../../interfaces/adapters/ll-adapter/IOracle.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title LiquidLaneAdapter
/// @notice Single-vault adapter for issuer-facing instant redemptions backed by factory-created redemption accounts.
contract LiquidLaneAdapter is EIP712, Adapter, PausableUpgradeable, ILiquidLaneAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Registry used to resolve token-specific redemption account factories.
    address internal immutable ACCOUNT_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc ILiquidLaneAdapter
    address public pauser;
    /// @inheritdoc ILiquidLaneAdapter
    address public unpauser;
    /// @inheritdoc ILiquidLaneAdapter
    address public marketMaker;
    /// @inheritdoc ILiquidLaneAdapter
    bool public marketMakerCanAcquire;
    /// @inheritdoc ILiquidLaneAdapter
    address[] public tokensToRedeem;
    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => uint256 amount) public limit;
    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => uint256 ppm) public minDiscount;

    /// @inheritdoc ILiquidLaneAdapter
    mapping(address who => address) public receiver;
    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => mapping(address marketMaker => uint256 amount)) public acquireBalance;

    /// @inheritdoc ILiquidLaneAdapter
    mapping(address marketMaker => mapping(address filler => bool)) public isFiller;
    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => mapping(uint256 nonce => bool)) public isUsedNonce;

    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => address account) public accounts;

    /// @dev Tracks whether a token is currently active for redemption.
    mapping(address tokenToRedeem => bool exists) internal _isTokenToRedeem;

    /// @dev Set while the adapter is funding a swap through VaultV2.
    bool internal transient _inSwap;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory, address accountRegistry)
        EIP712("LiquidLaneAdapter", "1")
        Adapter(vaultFactory, adapterFactory)
    {
        ACCOUNT_REGISTRY = accountRegistry;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function allocatable() public view override(Adapter, IAdapter) returns (uint256) {
        return _inSwap ? super.allocatable() : 0;
    }

    /// @inheritdoc IAdapter
    function freeAssets() public view override(Adapter, IAdapter) returns (uint256 assets) {
        address asset = IERC4626(vault).asset();
        for (uint256 i; i < tokensToRedeem.length; ++i) {
            assets += IERC20(asset).balanceOf(accounts[tokensToRedeem[i]]);
        }
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256 assets) {
        for (uint256 i; i < tokensToRedeem.length; ++i) {
            assets += IAccount(accounts[tokensToRedeem[i]]).totalAssets();
        }
    }

    /// @inheritdoc ILiquidLaneAdapter
    function getMaxAssets(address tokenToRedeem) public returns (uint256 assets) {
        uint256 acquireAssets = acquireBalance[tokenToRedeem][owner()];
        if (marketMaker != owner()) {
            acquireAssets += acquireBalance[tokenToRedeem][marketMaker];
        }
        address delegator = IVaultV2(vault).delegator();
        if (IUniversalDelegator(delegator).sweepPending() > 0) {
            return acquireAssets;
        }
        assets = Math.min(
            IUniversalDelegator(delegator).limitOf(address(this)).saturatingSub(totalAssets()),
            IVaultV2(vault).withdrawable()
        );
        assets = Math.min(assets, limit[tokenToRedeem].saturatingSub(IAccount(accounts[tokenToRedeem]).totalAssets()));
        return acquireAssets + assets;
    }

    /// @inheritdoc ILiquidLaneAdapter
    function getMaxRate(address tokenToRedeem) public view returns (uint256) {
        return
            _getOraclePrice(tokenToRedeem).mulDiv(DISCOUNT_PRECISION - minDiscount[tokenToRedeem], DISCOUNT_PRECISION);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function getAmountOut(address tokenToRedeem, uint256 amountIn) public view returns (uint256) {
        return amountIn.mulDiv(
            _getOraclePrice(tokenToRedeem) * 10 ** IERC20Metadata(IERC4626(vault).asset()).decimals(),
            1e18 * 10 ** IERC20Metadata(tokenToRedeem).decimals()
        );
    }

    /// @inheritdoc ILiquidLaneAdapter
    function getTokensToRedeemLength() public view returns (uint256) {
        return tokensToRedeem.length;
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc ILiquidLaneAdapter
    function setReceiver(address newReceiver) public {
        if (newReceiver == address(0)) {
            revert InvalidReceiver();
        }

        receiver[msg.sender] = newReceiver;

        emit SetReceiver(msg.sender, newReceiver);
    }

    /* PUBLIC FUNCTIONS (MARKET MAKER) */

    /// @inheritdoc ILiquidLaneAdapter
    function swap(Swap calldata swap) public {
        _validateSwapAccount(msg.sender);
        _swap(swap);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function swap(SignedSwap calldata signedSwap, bytes calldata signature) public {
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
                signedSwap.signer, _hashTypedDataV4(keccak256(abi.encode(SIGNED_SWAP_TYPEHASH, signedSwap))), signature
            )) {
            revert InvalidSignature();
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

    /// @inheritdoc ILiquidLaneAdapter
    function swap(
        DiscountSwap calldata discountSwap,
        bytes calldata protocolSignature,
        address recipient,
        uint256 amountIn
    ) public returns (uint256 amountOut) {
        Discount calldata discount = discountSwap.discount;
        _validateSwapAccount(discount.signer);
        if (discount.deadline < block.timestamp || discountSwap.protocolDeadline < block.timestamp) {
            revert ExpiredSwap();
        }
        if (isUsedNonce[discount.tokenToRedeem][discount.nonce]) {
            revert AlreadyUsedNonce();
        }
        if (discount.discount < minDiscount[discount.tokenToRedeem] || discount.discount > DISCOUNT_PRECISION) {
            revert InvalidDiscount();
        }
        if (!SignatureChecker.isValidSignatureNow(
                discount.signer, _hashTypedDataV4(_hashDiscount(discount)), discountSwap.signerSignature
            )) {
            revert InvalidSignature();
        }
        if (!SignatureChecker.isValidSignatureNow(
                discount.protocol,
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            DISCOUNT_SWAP_TYPEHASH,
                            _hashDiscount(discount),
                            keccak256(discountSwap.signerSignature),
                            discountSwap.protocolDeadline
                        )
                    )
                ),
                protocolSignature
            )) {
            revert InvalidSignature();
        }

        amountOut = getAmountOut(discount.tokenToRedeem, amountIn)
            .mulDiv(DISCOUNT_PRECISION - discount.discount, DISCOUNT_PRECISION);
        _swap(Swap({recipient: recipient, tokenIn: discount.tokenToRedeem, amountIn: amountIn, amountOut: amountOut}));
    }

    /// @inheritdoc ILiquidLaneAdapter
    function setFiller(address filler, bool status) public {
        if (owner() != msg.sender && marketMaker != msg.sender) {
            revert InvalidCaller();
        }

        isFiller[marketMaker][filler] = status;

        emit SetFiller(marketMaker, filler, status);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function invalidateNonce(address tokenToRedeem, uint256 nonce) public {
        if (owner() != msg.sender && marketMaker != msg.sender && !isFiller[marketMaker][msg.sender]) {
            revert InvalidCaller();
        }

        isUsedNonce[tokenToRedeem][nonce] = true;

        emit InvalidateNonce(tokenToRedeem, nonce);
    }

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc ILiquidLaneAdapter
    function depositToAcquire(address tokenToRedeem, uint256 amount) public {
        if (owner() != msg.sender && (!marketMakerCanAcquire || marketMaker != msg.sender)) {
            revert DepositNotAllowed();
        }
        if (receiver[msg.sender] == address(0)) {
            revert InvalidReceiver();
        }

        IERC20(IERC4626(vault).asset()).safeTransferFrom(msg.sender, address(this), amount);

        acquireBalance[tokenToRedeem][msg.sender] += amount;

        emit DepositToAcquire(msg.sender, tokenToRedeem, amount);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function withdrawToAcquire(address tokenToRedeem, uint256 amount) public {
        acquireBalance[tokenToRedeem][msg.sender] -= amount;

        IERC20(IERC4626(vault).asset()).safeTransfer(msg.sender, amount);

        emit WithdrawToAcquire(msg.sender, tokenToRedeem, amount);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function setMarketMaker(address newMarketMaker, bool newCanAcquire) public onlyOwner {
        marketMaker = newMarketMaker;
        marketMakerCanAcquire = newCanAcquire;

        emit SetMarketMaker(newMarketMaker, newCanAcquire);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function setPauser(address newPauser) public onlyOwner {
        pauser = newPauser;

        emit SetPauser(newPauser);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function setUnpauser(address newUnpauser) public onlyOwner {
        unpauser = newUnpauser;

        emit SetUnpauser(newUnpauser);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function pause() public {
        if (msg.sender != pauser) {
            revert InvalidCaller();
        }
        _pause();
    }

    /// @inheritdoc ILiquidLaneAdapter
    function unpause() public {
        if (msg.sender != unpauser) {
            revert InvalidCaller();
        }
        _unpause();
    }

    /// @inheritdoc ILiquidLaneAdapter
    function addTokenToRedeem(address tokenToRedeem) public onlyOwner {
        if (_isTokenToRedeem[tokenToRedeem]) {
            revert InvalidTokenToRedeem();
        }
        if (tokensToRedeem.length >= MAX_TOKENS_TO_REDEEM) {
            revert TooManyTokensToRedeem();
        }
        if (accounts[tokenToRedeem] == address(0)) {
            address accountFactory =
                IAccountRegistry(ACCOUNT_REGISTRY).accountFactories(IERC4626(vault).asset(), tokenToRedeem);
            accounts[tokenToRedeem] = IMigratablesFactory(accountFactory)
                .create(IMigratablesFactory(accountFactory).lastVersion(), owner(), abi.encode(vault, address(this)));
        }

        _isTokenToRedeem[tokenToRedeem] = true;
        tokensToRedeem.push(tokenToRedeem);

        emit AddTokenToRedeem(tokenToRedeem, accounts[tokenToRedeem]);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function removeTokenToRedeem(address tokenToRedeem) public onlyOwner {
        if (!_isTokenToRedeem[tokenToRedeem]) {
            revert InvalidTokenToRedeem();
        }
        if (IAccount(accounts[tokenToRedeem]).totalAssets() > 0) {
            revert AccountHasAssets();
        }

        for (uint256 i; i < tokensToRedeem.length; ++i) {
            if (tokenToRedeem == tokensToRedeem[i]) {
                tokensToRedeem[i] = tokensToRedeem[tokensToRedeem.length - 1];
                tokensToRedeem.pop();
                _isTokenToRedeem[tokenToRedeem] = false;
                limit[tokenToRedeem] = 0;

                emit RemoveTokenToRedeem(tokenToRedeem);
                return;
            }
        }
        revert InvalidTokenToRedeem();
    }

    /// @inheritdoc ILiquidLaneAdapter
    function setLimit(address tokenToRedeem, uint256 newLimit) public onlyOwner {
        if (!_isTokenToRedeem[tokenToRedeem]) {
            revert InvalidTokenToRedeem();
        }

        limit[tokenToRedeem] = newLimit;

        emit SetLimit(tokenToRedeem, newLimit);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function setMinDiscount(address tokenToRedeem, uint256 newMinDiscount) public onlyOwner {
        if (newMinDiscount > DISCOUNT_PRECISION) {
            revert InvalidDiscount();
        }

        minDiscount[tokenToRedeem] = newMinDiscount;

        emit SetMinDiscount(tokenToRedeem, newMinDiscount);
    }

    /// @inheritdoc IAdapter
    function deallocate(uint256) public override(Adapter, IAdapter) onlyDelegator returns (uint256 deallocated) {
        address asset = IERC4626(vault).asset();
        for (uint256 i; i < tokensToRedeem.length; ++i) {
            address account = accounts[tokensToRedeem[i]];
            // Sweep the account's full realized asset balance to the vault.
            uint256 amount = IERC20(asset).balanceOf(account);
            if (amount == 0) {
                continue;
            }
            // Reduce the outstanding vault-funded allocation by the realized proceeds (saturating: proceeds
            // include the instant-redemption discount and yield on top of the cash principal originally deployed).
            IERC20(asset).safeTransferFrom(account, address(this), amount);
            deallocated += amount;
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the account's oracle price for a token-to-redeem, denominated in the vault asset (1e18).
    /// @param tokenToRedeem The token being priced.
    /// @return price The token price in 1e18 precision.
    function _getOraclePrice(address tokenToRedeem) internal view returns (uint256 price) {
        price = IOracle(IAccount(accounts[tokenToRedeem]).ORACLE()).getPrice();
        if (price == 0) {
            revert InvalidOracle();
        }
    }

    /// @dev Reverts if `account` is not authorized to swap for the vault.
    /// @param account The account being validated.
    function _validateSwapAccount(address account) internal view {
        if (account != owner() && account != marketMaker && !isFiller[marketMaker][account]) {
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
                discount.tokenToRedeem,
                discount.discount,
                discount.signer,
                discount.protocol,
                discount.nonce,
                discount.deadline
            )
        );
    }

    /// @dev Triggers adapter allocation through the current delegator.
    /// @param amount The vault-asset amount requested by the vault.
    function _allocate(uint256 amount) internal pure override returns (uint256) {
        return amount;
    }

    /// @dev Executes a direct or delegated swap after caller authentication has already succeeded.
    /// @param swap The swap payload to execute.
    function _swap(Swap memory swap) internal whenNotPaused {
        if (!_isTokenToRedeem[swap.tokenIn]) {
            revert InvalidTokenToRedeem();
        }
        if (
            swap.amountOut
                > getAmountOut(swap.tokenIn, swap.amountIn)
                    .mulDiv(DISCOUNT_PRECISION - minDiscount[swap.tokenIn], DISCOUNT_PRECISION)
        ) {
            revert InvalidSwapRate();
        }

        uint256 curatorAcquireBalance = acquireBalance[swap.tokenIn][owner()];
        uint256 marketMakerAcquireBalance = owner() == marketMaker ? 0 : acquireBalance[swap.tokenIn][marketMaker];
        uint256 tokenOutToAcquire = Math.min(swap.amountOut, curatorAcquireBalance + marketMakerAcquireBalance);

        uint256 tokenOutToAllocate = swap.amountOut - tokenOutToAcquire;
        if (IAccount(accounts[swap.tokenIn]).totalAssets() + tokenOutToAllocate > limit[swap.tokenIn]) {
            revert LimitExceeded();
        }

        if (tokenOutToAllocate > 0) {
            _inSwap = true;
            if (
                IUniversalDelegator(IVaultV2(vault).delegator()).allocateExact(address(this), tokenOutToAllocate)
                    < tokenOutToAllocate
            ) {
                revert InsufficientAllocate();
            }
            _inSwap = false;
        }

        uint256 tokenInAcquired;
        if (tokenOutToAcquire > 0) {
            tokenInAcquired = tokenOutToAcquire.mulDiv(swap.amountIn, swap.amountOut);
            uint256 curatorAcquireBalanceSpent = (tokenOutToAcquire + 1) >> 1;
            if (curatorAcquireBalanceSpent > curatorAcquireBalance) {
                curatorAcquireBalanceSpent = curatorAcquireBalance;
            }
            uint256 marketMakerAcquireBalanceSpent = tokenOutToAcquire - curatorAcquireBalanceSpent;
            if (marketMakerAcquireBalanceSpent > marketMakerAcquireBalance) {
                marketMakerAcquireBalanceSpent = marketMakerAcquireBalance;
                curatorAcquireBalanceSpent = tokenOutToAcquire - marketMakerAcquireBalanceSpent;
            }

            acquireBalance[swap.tokenIn][owner()] = curatorAcquireBalance - curatorAcquireBalanceSpent;
            if (owner() != marketMaker) {
                acquireBalance[swap.tokenIn][marketMaker] = marketMakerAcquireBalance - marketMakerAcquireBalanceSpent;
            }

            uint256 marketMakerAcquired = marketMakerAcquireBalanceSpent.mulDiv(tokenInAcquired, tokenOutToAcquire);
            uint256 curatorAcquired = tokenInAcquired - marketMakerAcquired;
            if (curatorAcquired > 0) {
                IERC20(swap.tokenIn).safeTransfer(receiver[owner()], curatorAcquired);
            }
            if (marketMakerAcquired > 0) {
                IERC20(swap.tokenIn).safeTransfer(receiver[marketMaker], marketMakerAcquired);
            }
        }

        uint256 tokenInToRedeem = swap.amountIn - tokenInAcquired;
        if (tokenInToRedeem > 0) {
            address account = accounts[swap.tokenIn];
            IERC20(swap.tokenIn).safeTransfer(account, tokenInToRedeem);
            IAccount(account).sync();
        }

        IERC20(IERC4626(vault).asset()).safeTransfer(swap.recipient, swap.amountOut);

        emit DoSwap(swap);
    }

    /* INITIALIZATION */

    /// @dev Initializes the pause roles.
    function __initialize(address, bytes memory data) internal override {
        InitParams memory params = abi.decode(data, (InitParams));

        pauser = params.pauser;
        unpauser = params.unpauser;

        emit Initialize(params);
    }
}

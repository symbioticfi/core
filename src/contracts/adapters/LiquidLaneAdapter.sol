// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Adapter} from "./Adapter.sol";

import {
    DISCOUNT_SWAP_TYPEHASH,
    DISCOUNT_TYPEHASH,
    DISCOUNT_PRECISION,
    ILiquidLaneAdapter,
    MAX_TOKENS_TO_REDEEM,
    SIGNED_SWAP_TYPEHASH
} from "../../interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IAccount} from "../../interfaces/adapters/ll-adapter/IAccount.sol";
import {ILiquidLaneRegistry} from "../../interfaces/adapters/ILiquidLaneRegistry.sol";
import {ILiquidLaneOracle as IOracle} from "../../interfaces/adapters/ll-adapter/ILiquidLaneOracle.sol";
import {IMigratablesFactory} from "../../interfaces/common/IMigratablesFactory.sol";
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
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* STATE VARIABLES */

    /// @inheritdoc ILiquidLaneAdapter
    address public marketMaker;
    /// @inheritdoc ILiquidLaneAdapter
    address public pauser;
    /// @inheritdoc ILiquidLaneAdapter
    address public unpauser;
    /// @notice Tokens-to-redeem configured for the vault.
    address[] public tokensToRedeem;
    /// @inheritdoc ILiquidLaneAdapter
    bool public marketMakerCanAcquire;
    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => uint256 amount) public limit;
    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => uint256 ppm) public minDiscount;
    /// @notice Vault-funded collateral currently outstanding per token-to-redeem.
    mapping(address tokenToRedeem => uint256 amount) public allocated;

    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => uint256 amount) public curatorAcquireBalance;
    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => mapping(address marketMaker => uint256 amount)) public marketMakerAcquireBalances;
    /// @notice Total acquisition collateral deposited.
    uint256 public acquireTotal;
    /// @inheritdoc ILiquidLaneAdapter
    mapping(address who => address) public receiver;

    /// @inheritdoc ILiquidLaneAdapter
    mapping(address marketMaker => mapping(address filler => bool)) public isFiller;
    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => mapping(uint256 nonce => bool)) public isUsedNonce;

    /// @inheritdoc ILiquidLaneAdapter
    mapping(address tokenToRedeem => address account) public accounts;

    /// @dev Set while the adapter is funding a swap through VaultV2. Transient: only meaningful within the
    ///      single swap transaction that reads it back through the delegator's `allocatable()` callback.
    bool internal transient _inSwap;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory)
        EIP712("LiquidLaneAdapter", "1")
        Adapter(vaultFactory, adapterFactory)
    {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function allocatable() public view override(Adapter, IAdapter) returns (uint256) {
        return _inSwap ? super.allocatable() : 0;
    }

    /// @inheritdoc ILiquidLaneAdapter
    function paused() public view override(PausableUpgradeable, ILiquidLaneAdapter) returns (bool) {
        return super.paused();
    }

    /// @inheritdoc IAdapter
    function freeAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return IERC20(IERC4626(vault).asset()).balanceOf(address(this)).saturatingSub(acquireTotal);
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256 assets) {
        assets = freeAssets();
        for (uint256 i; i < tokensToRedeem.length; ++i) {
            assets += IAccount(accounts[tokensToRedeem[i]]).totalAssets();
        }
    }

    /// @inheritdoc ILiquidLaneAdapter
    function getMaxAssets(address tokenToRedeem) public view returns (uint256) {
        uint256 available = freeAssets();
        address delegator = IVaultV2(vault).delegator();
        if (delegator != address(0)) {
            available += Math.min(
                IUniversalDelegator(delegator).limitOf(address(this)).saturatingSub(totalAssets()),
                IVaultV2(vault).freeAssets()
            );
        }

        return Math.min(limit[tokenToRedeem] - allocated[tokenToRedeem], available)
            + curatorAcquireBalance[tokenToRedeem] + marketMakerAcquireBalances[tokenToRedeem][marketMaker];
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
        uint256 amountIn,
        uint256 amountOut
    ) public {
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

        if (
            amountOut
                > getAmountOut(discount.tokenToRedeem, amountIn)
                    .mulDiv(DISCOUNT_PRECISION - discount.discount, DISCOUNT_PRECISION)
        ) {
            revert InvalidSwapRate();
        }

        isUsedNonce[discount.tokenToRedeem][discount.nonce] = true;

        _swap(Swap({recipient: recipient, tokenIn: discount.tokenToRedeem, amountIn: amountIn, amountOut: amountOut}));
    }

    /// @inheritdoc ILiquidLaneAdapter
    function setFiller(address filler, bool isAuthorized) public {
        if (owner() != msg.sender && marketMaker != msg.sender) {
            revert InvalidCaller();
        }

        isFiller[marketMaker][filler] = isAuthorized;

        emit SetFiller(marketMaker, filler, isAuthorized);
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
        bool isOwner = owner() == msg.sender;
        if (!isOwner && (!marketMakerCanAcquire || marketMaker != msg.sender)) {
            revert DepositNotAllowed();
        }
        if (receiver[msg.sender] == address(0)) {
            revert InvalidReceiver();
        }

        IERC20(IERC4626(vault).asset()).safeTransferFrom(msg.sender, address(this), amount);
        acquireTotal += amount;

        if (isOwner) {
            curatorAcquireBalance[tokenToRedeem] += amount;
        } else {
            marketMakerAcquireBalances[tokenToRedeem][marketMaker] += amount;
        }

        emit DepositToAcquire(tokenToRedeem, amount);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function withdrawToAcquire(address tokenToRedeem, uint256 amount) public {
        if (owner() == msg.sender) {
            curatorAcquireBalance[tokenToRedeem] -= amount;
        } else {
            marketMakerAcquireBalances[tokenToRedeem][msg.sender] -= amount;
        }
        acquireTotal -= amount;
        IERC20(IERC4626(vault).asset()).safeTransfer(msg.sender, amount);

        emit WithdrawToAcquire(tokenToRedeem, amount);
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
        if (tokenToRedeem == address(0) || accounts[tokenToRedeem] != address(0)) {
            revert InvalidTokenToRedeem();
        }
        if (tokensToRedeem.length >= MAX_TOKENS_TO_REDEEM) {
            revert InvalidLimit();
        }

        address accountFactory = ILiquidLaneRegistry(FACTORY).accountFactories(tokenToRedeem);
        if (accountFactory == address(0)) {
            revert InvalidAccountFactory();
        }

        address account = IMigratablesFactory(accountFactory)
            .create(
                IMigratablesFactory(accountFactory).lastVersion(),
                owner(),
                abi.encode(address(this), vault, tokenToRedeem)
            );
        accounts[tokenToRedeem] = account;
        tokensToRedeem.push(tokenToRedeem);

        emit AddTokenToRedeem(tokenToRedeem, account);
    }

    /// @inheritdoc ILiquidLaneAdapter
    function removeTokenToRedeem(address tokenToRedeem) public onlyOwner {
        if (allocated[tokenToRedeem] > 0) {
            revert InvalidLimit();
        }

        for (uint256 i; i < tokensToRedeem.length; ++i) {
            if (tokenToRedeem == tokensToRedeem[i]) {
                tokensToRedeem[i] = tokensToRedeem[tokensToRedeem.length - 1];
                tokensToRedeem.pop();

                emit RemoveTokenToRedeem(tokenToRedeem, accounts[tokenToRedeem]);
                delete accounts[tokenToRedeem];
                delete limit[tokenToRedeem];
                delete minDiscount[tokenToRedeem];
                return;
            }
        }

        revert InvalidTokenToRedeem();
    }

    /// @inheritdoc ILiquidLaneAdapter
    function setLimit(address tokenToRedeem, uint256 newLimit) public onlyOwner {
        if (allocated[tokenToRedeem] > newLimit) {
            revert InvalidLimit();
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

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the account's oracle price for a token-to-redeem, denominated in the vault asset (1e18).
    /// @param tokenToRedeem The token being priced.
    /// @return price The token price in 1e18 precision.
    function _getOraclePrice(address tokenToRedeem) internal view returns (uint256 price) {
        price = IOracle(IAccount(_getAccount(tokenToRedeem)).ORACLE()).getPrice();
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
    /// @param amount The collateral amount requested by the vault.
    function _allocate(uint256 amount) internal pure override returns (uint256) {
        return amount;
    }

    /// @dev Pulls all available collateral from redemption accounts for the vault.
    /// @return deallocated The collateral returned from redemption accounts.
    function _deallocate(uint256) internal override returns (uint256 deallocated) {
        address asset = IERC4626(vault).asset();
        for (uint256 i; i < tokensToRedeem.length; ++i) {
            address tokenToRedeem = tokensToRedeem[i];
            address account = accounts[tokenToRedeem];
            if (account.code.length == 0) {
                continue;
            }
            // Sweep the account's full realized asset balance to the vault.
            uint256 amount = IERC20(asset).balanceOf(account);
            if (amount == 0) {
                continue;
            }
            // Reduce the outstanding vault-funded allocation by the realized proceeds (saturating: proceeds
            // include the instant-redemption discount and yield on top of the cash principal originally deployed).
            allocated[tokenToRedeem] = allocated[tokenToRedeem].saturatingSub(amount);
            IERC20(asset).safeTransferFrom(account, address(this), amount);
            deallocated += amount;
        }
    }

    /// @dev Executes a direct or delegated swap after caller authentication has already succeeded.
    /// @param swap The swap payload to execute.
    function _swap(Swap memory swap) internal whenNotPaused {
        if (
            swap.amountOut
                > getAmountOut(swap.tokenIn, swap.amountIn)
                    .mulDiv(DISCOUNT_PRECISION - minDiscount[swap.tokenIn], DISCOUNT_PRECISION)
        ) {
            revert InvalidSwapRate();
        }

        uint256 curCuratorAcquireBalance = curatorAcquireBalance[swap.tokenIn];
        uint256 curMarketMakerAcquireBalance = marketMakerAcquireBalances[swap.tokenIn][marketMaker];
        uint256 tokenOutToAcquire = Math.min(swap.amountOut, curCuratorAcquireBalance + curMarketMakerAcquireBalance);

        uint256 tokenOutToAllocate = swap.amountOut - tokenOutToAcquire;
        if (allocated[swap.tokenIn] + tokenOutToAllocate > limit[swap.tokenIn]) {
            revert InvalidCollateralOut();
        }
        allocated[swap.tokenIn] += tokenOutToAllocate;

        if (tokenOutToAllocate > 0) {
            uint256 tokenOutToPull = tokenOutToAllocate.saturatingSub(freeAssets());
            if (tokenOutToPull > 0) {
                _inSwap = true;
                if (
                    IUniversalDelegator(IVaultV2(vault).delegator()).allocate(address(this), tokenOutToPull)
                        < tokenOutToPull
                ) {
                    revert InsufficientAllocation();
                }
                _inSwap = false;
            }
        }

        uint256 tokenInAcquired;
        if (tokenOutToAcquire > 0) {
            tokenInAcquired = tokenOutToAcquire.mulDiv(swap.amountIn, swap.amountOut);
            uint256 curatorAcquireBalanceSpent = (tokenOutToAcquire + 1) >> 1;
            if (curatorAcquireBalanceSpent > curCuratorAcquireBalance) {
                curatorAcquireBalanceSpent = curCuratorAcquireBalance;
            }
            uint256 marketMakerAcquireBalanceSpent = tokenOutToAcquire - curatorAcquireBalanceSpent;
            if (marketMakerAcquireBalanceSpent > curMarketMakerAcquireBalance) {
                marketMakerAcquireBalanceSpent = curMarketMakerAcquireBalance;
                curatorAcquireBalanceSpent = tokenOutToAcquire - marketMakerAcquireBalanceSpent;
            }

            curatorAcquireBalance[swap.tokenIn] = curCuratorAcquireBalance - curatorAcquireBalanceSpent;
            marketMakerAcquireBalances[swap.tokenIn][marketMaker] =
                curMarketMakerAcquireBalance - marketMakerAcquireBalanceSpent;
            acquireTotal -= tokenOutToAcquire;

            uint256 marketMakerAcquired = marketMakerAcquireBalanceSpent.mulDiv(tokenInAcquired, tokenOutToAcquire);
            uint256 curatorAcquired = tokenInAcquired - marketMakerAcquired;
            if (curatorAcquired > 0) {
                address curatorReceiver = receiver[owner()];
                if (curatorReceiver == address(0)) {
                    revert InvalidReceiver();
                }
                IERC20(swap.tokenIn).safeTransfer(curatorReceiver, curatorAcquired);
            }
            if (marketMakerAcquired > 0) {
                address marketMakerReceiver = receiver[marketMaker];
                if (marketMakerReceiver == address(0)) {
                    revert InvalidReceiver();
                }
                IERC20(swap.tokenIn).safeTransfer(marketMakerReceiver, marketMakerAcquired);
            }
        }

        uint256 tokenInToRedeem = swap.amountIn - tokenInAcquired;
        if (tokenInToRedeem > 0) {
            address account = _getAccount(swap.tokenIn);
            IERC20(swap.tokenIn).safeTransfer(account, tokenInToRedeem);
            IAccount(account).requestRedeem();
        }

        IERC20(IERC4626(vault).asset()).safeTransfer(swap.recipient, swap.amountOut);

        emit DoSwap(swap);
    }

    /// @dev Returns the created account for a `tokenToRedeem`.
    /// @param tokenToRedeem The token-to-redeem address.
    /// @return account The created account address.
    function _getAccount(address tokenToRedeem) internal view returns (address account) {
        account = accounts[tokenToRedeem];
        if (account == address(0)) {
            revert InvalidTokenToRedeem();
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the pauser and unpauser to the owner.
    function __initialize(address, bytes memory) internal override {
        address curOwner = owner();
        pauser = curOwner;
        unpauser = curOwner;

        emit SetPauser(curOwner);
        emit SetUnpauser(curOwner);
    }
}

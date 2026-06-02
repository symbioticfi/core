// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {CoWSwapConverter} from "../../common/CoWSwapConverter.sol";
import {MigratableEntity} from "../../../common/MigratableEntity.sol";

import {
    IMidasAccount,
    REQUEST_STATUS_PENDING
} from "../../../../interfaces/adapters/ll-adapter/accounts/IMidasAccount.sol";
import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/accounts/IMidasRedemptionVault.sol";
import {IAccount} from "../../../../interfaces/adapters/ll-adapter/IAccount.sol";
import {ILiquidLaneOracle} from "../../../../interfaces/adapters/ll-adapter/ILiquidLaneOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MidasAccount
/// @notice Base account integration that submits Midas standard redemption requests and converts non-asset
///         proceeds into the vault asset through CoW Protocol orders. Holdings are valued via the oracle, and
///         redemption-token proceeds are assumed to be 1:1 with the vault asset.
abstract contract MidasAccount is MigratableEntity, CoWSwapConverter, IMidasAccount {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IMidasAccount
    address public immutable TOKEN_TO_REDEEM;
    /// @inheritdoc IAccount
    address public immutable ORACLE;
    /// @inheritdoc IMidasAccount
    address public immutable REDEMPTION_TOKEN;
    /// @inheritdoc IMidasAccount
    address public immutable REDEMPTION_VAULT;
    /// @notice Minimum delay between creating consecutive Midas redemption requests. Batching held inventory once
    ///         per cooldown bounds the number of concurrent pending requests to about (max redemption delay / COOLDOWN).
    uint256 public immutable COOLDOWN;
    /// @dev 10 ** TOKEN_TO_REDEEM decimals, cached at construction.
    uint256 internal immutable TO_ASSETS_DIVISOR;

    /* STATE VARIABLES */

    /// @inheritdoc IMidasAccount
    address public adapter;
    /// @inheritdoc IAccount
    address public vault;
    /// @notice Timestamp of the most recently created Midas redemption request (zero before the first one).
    uint256 public lastRequestTime;

    /// @dev 10 ** vault-asset decimals, cached at init (the asset comes from the per-account vault).
    uint256 internal _assetUnit;

    /// @dev Outstanding Midas redemption request ids (pending plus not-yet-pruned terminal requests).
    uint256[] internal _requestIds;

    /* MODIFIERS */

    modifier onlyAdapter() {
        if (msg.sender != adapter) {
            revert NotAdapter();
        }
        _;
    }

    /* CONSTRUCTOR */

    constructor(
        address oracle,
        address factory,
        uint256 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) MigratableEntity(factory) CoWSwapConverter(cowSwapSettlement, cowSwapVaultRelayer) {
        TOKEN_TO_REDEEM = tokenToRedeem;
        TO_ASSETS_DIVISOR = 1e18 * 10 ** IERC20Metadata(tokenToRedeem).decimals();
        ORACLE = oracle;
        REDEMPTION_TOKEN = redemptionToken;
        REDEMPTION_VAULT = redemptionVault;
        COOLDOWN = cooldown;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAccount
    function totalAssets() public view virtual returns (uint256 assets) {
        address asset = IERC4626(vault).asset();
        assets = IERC20(asset).balanceOf(address(this));
        if (REDEMPTION_TOKEN != asset) {
            assets += IERC20(REDEMPTION_TOKEN).balanceOf(address(this));
        }

        // Fetch the oracle price once and reuse it for held inventory and every current-rate pending request.
        uint256 price = ILiquidLaneOracle(ORACLE).getPrice();

        uint256 held = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (held > 0) {
            assets += _toAssets(held, price);
        }

        // Add the value of in-flight (pending) requests, valued per account mode.
        assets += _pendingAssets(price);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IAccount
    function sync() public nonReentrant {
        // Prune terminal (processed or canceled) requests so totalAssets() and the request set stay tight.
        for (uint256 i = _requestIds.length; i > 0; --i) {
            (,, uint8 status,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(_requestIds[i - 1]);
            if (status == REQUEST_STATUS_PENDING) {
                continue;
            }

            _requestIds[i - 1] = _requestIds[_requestIds.length - 1];
            _requestIds.pop();
        }

        // Batch held inventory into a single new request at most once per cooldown (the first request is exempt),
        // which bounds the number of concurrent pending requests.
        if (lastRequestTime != 0 && block.timestamp < lastRequestTime + COOLDOWN) {
            return;
        }
        uint256 held = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (held == 0) {
            return;
        }

        // Redeem into the vault asset when Midas prices it directly, otherwise into the fallback redemption token.
        address asset = IERC4626(vault).asset();
        (address dataFeed,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).tokensConfig(asset);
        _requestIds.push(
            IMidasRedemptionVault(REDEMPTION_VAULT)
                .redeemRequest(dataFeed == address(0) ? REDEMPTION_TOKEN : asset, held)
        );
        lastRequestTime = block.timestamp;
    }

    /// @inheritdoc CoWSwapConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data) public override {
        sync();

        address asset = IERC4626(vault).asset();
        // The token-to-redeem must go through the Midas redemption flow, not be sold via CoW.
        if (tokenIn == asset || tokenIn == TOKEN_TO_REDEEM) {
            revert InvalidTokenIn();
        }
        if (tokenOut != asset) {
            revert InvalidTokenOut();
        }
        super.convert(tokenIn, amountIn, tokenOut, data);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Prices a token-to-redeem amount in vault assets at the given token-to-redeem rate (base 1e18).
    function _toAssets(uint256 amount, uint256 rate) internal view returns (uint256) {
        return amount.mulDiv(rate * _assetUnit, TO_ASSETS_DIVISOR);
    }

    /// @dev Returns the total vault-asset value of in-flight (pending) Midas requests for this account mode.
    /// @param price The current token-to-redeem oracle price (base 1e18), used by compounding accounts.
    function _pendingAssets(uint256 price) internal view virtual returns (uint256);

    /* INITIALIZATION */

    /// @dev Initializes the account for a liquidity lane adapter and vault and grants the converter role to the owner.
    function _initialize(uint64, address, bytes memory data) internal override {
        (address initAdapter, address initVault,) = abi.decode(data, (address, address, address));

        adapter = initAdapter;
        vault = initVault;

        address asset = IERC4626(initVault).asset();
        _assetUnit = 10 ** IERC20Metadata(asset).decimals();

        // The adapter pulls realized proceeds via transferFrom; approve it once here instead of on every deallocate.
        IERC20(asset).forceApprove(initAdapter, type(uint256).max);
        IERC20(TOKEN_TO_REDEEM).forceApprove(REDEMPTION_VAULT, type(uint256).max);
        IERC20(asset).forceApprove(REDEMPTION_VAULT, type(uint256).max);

        address[] memory initConverters = new address[](1);
        initConverters[0] = owner();
        __CoWSwapConverter_init(initConverters);
    }
}

/// @title MidasCompAccount
/// @notice Midas account that values pending requests at the current oracle price until processing.
contract MidasCompAccount is MidasAccount {
    /* CONSTRUCTOR */

    constructor(
        address oracle,
        address factory,
        uint256 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    )
        MidasAccount(
            oracle,
            factory,
            cooldown,
            tokenToRedeem,
            redemptionToken,
            redemptionVault,
            cowSwapSettlement,
            cowSwapVaultRelayer
        )
    {}

    /* INTERNAL FUNCTIONS */

    /// @inheritdoc MidasAccount
    function _pendingAssets(uint256 price) internal view override returns (uint256) {
        // Every pending request prices at the current rate, so sum the amounts and convert once.
        uint256 amount;
        for (uint256 i; i < _requestIds.length; ++i) {
            (,, uint8 status, uint256 amountMToken,,) =
                IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(_requestIds[i]);
            if (status == REQUEST_STATUS_PENDING) {
                amount += amountMToken;
            }
        }
        return _toAssets(amount, price);
    }
}

/// @title MidasNonCompAccount
/// @notice Midas account that values pending requests at the oracle price recorded when the request is created.
contract MidasNonCompAccount is MidasAccount {
    /* CONSTRUCTOR */

    constructor(
        address oracle,
        address factory,
        uint256 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    )
        MidasAccount(
            oracle,
            factory,
            cooldown,
            tokenToRedeem,
            redemptionToken,
            redemptionVault,
            cowSwapSettlement,
            cowSwapVaultRelayer
        )
    {}

    /* INTERNAL FUNCTIONS */

    /// @inheritdoc MidasAccount
    function _pendingAssets(uint256) internal view override returns (uint256 assets) {
        // Each request locks its own creation-time rate, so value them individually.
        for (uint256 i; i < _requestIds.length; ++i) {
            (,, uint8 status, uint256 amountMToken, uint256 mTokenRate,) =
                IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(_requestIds[i]);
            if (status == REQUEST_STATUS_PENDING) {
                assets += _toAssets(amountMToken, mTokenRate);
            }
        }
    }
}

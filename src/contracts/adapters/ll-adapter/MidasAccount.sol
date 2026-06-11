// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";
import {CutoffPricer} from "./common/CutoffPricer.sol";

import {IMidasAccount, REQUEST_STATUS_PENDING} from "../../../interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IMidasRedemptionVault} from "../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IPriceDataOracle} from "../../../interfaces/adapters/ll-adapter/IPriceDataOracle.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MidasAccount
/// @notice Base account for Midas redemption integrations.
abstract contract MidasAccount is CooldownAccount, IMidasAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IMidasAccount
    address public immutable REDEMPTION_TOKEN;
    /// @inheritdoc IMidasAccount
    address public immutable REDEMPTION_VAULT;

    /* STATE VARIABLES */

    /// @inheritdoc IMidasAccount
    uint64[] public requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        REDEMPTION_TOKEN = redemptionToken;
        REDEMPTION_VAULT = redemptionVault;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value in vault assets.
    function _pendingAssets() internal view virtual returns (uint256);

    /// @dev Returns held fallback redemption-token value plus pending request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        if (REDEMPTION_TOKEN != _asset) {
            assets += _redemptionTokenToAssets(REDEMPTION_TOKEN, IERC20(REDEMPTION_TOKEN).balanceOf(address(this)));
        }

        assets += _pendingAssets();
    }

    /// @dev Clears Midas redemption requests that are no longer pending.
    function _finalizeRequests() internal virtual override {
        for (uint256 i = requestIds.length; i > 0; --i) {
            (,, uint8 status,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestIds[i - 1]);
            if (status == REQUEST_STATUS_PENDING) {
                continue;
            }

            requestIds[i - 1] = requestIds[requestIds.length - 1];
            requestIds.pop();
        }
    }

    /// @dev Submits held token-to-redeem inventory to the Midas redemption vault.
    function _requestRedeem() internal virtual override {
        (address dataFeed,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).tokensConfig(_asset);
        requestIds.push(
            uint64(
                IMidasRedemptionVault(REDEMPTION_VAULT)
                    .redeemRequest(
                        dataFeed == address(0) ? REDEMPTION_TOKEN : _asset,
                        IERC20(TOKEN_TO_REDEEM).balanceOf(address(this))
                    )
            )
        );
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal virtual override {
        super._initialize(initialVersion, initOwner, data);

        IERC20(TOKEN_TO_REDEEM).forceApprove(REDEMPTION_VAULT, type(uint256).max);
    }
}

/// @title MidasCompAccount
/// @notice Midas account that prices pending requests at the current oracle rate.
contract MidasCompAccount is MidasAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the compounding Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    ) MidasAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement) {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value using the current oracle rate.
    function _pendingAssets() internal view override returns (uint256) {
        uint256 amount;
        for (uint256 i; i < requestIds.length; ++i) {
            (,, uint8 status, uint256 amountMToken,,) =
                IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestIds[i]);
            if (status == REQUEST_STATUS_PENDING) {
                amount += amountMToken;
            }
        }
        if (amount == 0) {
            return 0;
        }
        return _tokenToRedeemToAssets(amount);
    }
}

/// @title MidasNonCompAccount
/// @notice Midas account that prices pending requests at their creation-time rate.
contract MidasNonCompAccount is MidasAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the non-compounding Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    ) MidasAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement) {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value using each request's locked rate.
    function _pendingAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < requestIds.length; ++i) {
            (,, uint8 status, uint256 amountMToken, uint256 mTokenRate,) =
                IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestIds[i]);
            if (status == REQUEST_STATUS_PENDING) {
                assets += _tokenToRedeemToAssets(amountMToken, mTokenRate);
            }
        }
    }
}

/// @title MidasCutoffAccount
/// @notice Midas account for cutoff-cohort redemptions: pending requests compound until the cohort
///         pricing date, then freeze at the first vault-feed print at/after it.
contract MidasCutoffAccount is MidasAccount, CutoffPricer {
    /* CONSTRUCTOR */

    /// @notice Creates the cutoff-cohort Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        uint48 initialCutoff,
        uint48 initialCutoffPeriod,
        uint48 valuationDelay,
        uint48 settlementDuration,
        address cowSwapSettlement
    )
        MidasAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement)
        CutoffPricer(initialCutoff, initialCutoffPeriod, valuationDelay, settlementDuration)
    {}

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @notice Updates the cutoff schedule. Only callable by the owner.
    function setCutoffSchedule(uint48 nextCutoff, uint48 period) public onlyOwner {
        _setCutoffSchedule(nextCutoff, period);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Submits inventory to the Midas redemption vault and registers the request's cohort.
    ///      Midas request ids are vault-global and monotonically increasing, so cohort keys are unique.
    function _requestRedeem() internal override {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        super._requestRedeem();
        _registerPending(requestIds[requestIds.length - 1], amount);
    }

    /// @dev Freezes cohort rates and clears Midas redemption requests that are no longer pending.
    function _finalizeRequests() internal override {
        for (uint256 i = requestIds.length; i > 0; --i) {
            uint256 index = i - 1;
            uint64 requestId = requestIds[index];

            _tryFreezePending(requestId);

            (,, uint8 status,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestId);
            if (status == REQUEST_STATUS_PENDING) {
                continue;
            }

            _clearPending(requestId);
            requestIds[index] = requestIds[requestIds.length - 1];
            requestIds.pop();
        }
    }

    /// @dev Returns pending request value priced by cutoff cohorts.
    function _pendingAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < requestIds.length; ++i) {
            assets += _pendingValue(requestIds[i]);
        }
    }

    /// @inheritdoc CutoffPricer
    function _cutoffPriceData() internal view override returns (uint256 price, uint48 updatedAt) {
        return IPriceDataOracle(ORACLE).getPriceData();
    }

    /// @inheritdoc CutoffPricer
    function _cutoffToAssets(uint256 amount, uint256 rate) internal view override returns (uint256 assets) {
        return _tokenToRedeemToAssets(amount, rate);
    }

    /* INITIALIZATION */

    /// @dev Initializes the account and applies the cutoff schedule.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        __CutoffPricer_init();
    }
}

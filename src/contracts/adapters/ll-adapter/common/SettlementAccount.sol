// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./CooldownAccount.sol";
import {CutoffPricer} from "./CutoffPricer.sol";

import {IPriceDataOracle} from "../../../../interfaces/adapters/ll-adapter/IPriceDataOracle.sol";
import {ISettlementAccount} from "../../../../interfaces/adapters/ll-adapter/ISettlementAccount.sol";
import {ISettlementSubAccount} from "../../../../interfaces/adapters/ll-adapter/ISettlementSubAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SettlementAccount
/// @notice Base account settling redemptions through per-request subaccounts priced by cutoff cohorts.
/// @dev Settlement is value-covered: a subaccount is only released once cumulative swept value (assets plus
///      tokens at sweep-time rates) covers its cohort value, making dust donations harmless (they reduce
///      the remaining receivable one-for-one) and keeping multi-tranche settlements and post-write-off
///      late settlements sweepable. Release additionally requires the cohort rate to be frozen (or the
///      entry written off), so pre-freeze oracle rate drift cannot flip coverage true and release a
///      subaccount early.
abstract contract SettlementAccount is CooldownAccount, CutoffPricer, ISettlementAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* STATE VARIABLES */

    /// @inheritdoc ISettlementAccount
    address[] public subAccounts;
    /// @inheritdoc ISettlementAccount
    mapping(uint256 key => uint256 assets) public receivedValues;

    /* CONSTRUCTOR */

    /// @notice Creates the settlement account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        uint48 initialCutoff,
        uint48 initialCutoffPeriod,
        uint48 valuationDelay,
        uint48 settlementDuration,
        address cowSwapSettlement
    )
        CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement)
        CutoffPricer(initialCutoff, initialCutoffPeriod, valuationDelay, settlementDuration)
    {}

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc ISettlementAccount
    function setCutoffSchedule(uint48 nextCutoff, uint48 period) public onlyOwner {
        _setCutoffSchedule(nextCutoff, period);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns subaccount holdings plus any remaining pending receivable not yet realized.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 length = subAccounts.length;
        for (uint256 i; i < length; ++i) {
            address subAccount = subAccounts[i];

            uint256 holdings = IERC20(_asset).balanceOf(subAccount);
            uint256 tokenBalance = IERC20(TOKEN_TO_REDEEM).balanceOf(subAccount);
            if (tokenBalance > 0) {
                holdings += _tokenToRedeemToAssets(tokenBalance);
            }

            assets += holdings + _remainingValue(uint160(subAccount)).saturatingSub(holdings);
        }
    }

    /// @dev Returns the unsettled portion of a subaccount's receivable (0 once written off).
    function _remainingValue(uint256 key) internal view returns (uint256 remaining) {
        (uint256 value, bool writtenOff) = _cohortValue(key);
        if (writtenOff) {
            return 0;
        }
        return value.saturatingSub(receivedValues[key]);
    }

    /// @dev Freezes cohort rates, sweeps subaccounts, and clears value-covered ones. A subaccount is only
    ///      cleared once its cohort rate is frozen (or the entry is written off), so pre-freeze rate drift
    ///      cannot release it early while later settlement tranches are still inbound.
    function _finalizeRequests() internal override {
        for (uint256 i = subAccounts.length; i > 0; --i) {
            uint256 index = i - 1;
            address subAccount = subAccounts[index];
            uint256 key = uint160(subAccount);

            _tryFreezePending(key);

            (uint256 sweptAssets, uint256 sweptTokenAmount) = ISettlementSubAccount(subAccount).sync();
            uint256 sweptValue = sweptAssets;
            if (sweptTokenAmount > 0) {
                sweptValue += _tokenToRedeemToAssets(sweptTokenAmount);
            }
            if (sweptValue > 0) {
                receivedValues[key] += sweptValue;
            }

            (uint256 value, bool writtenOff) = _cohortValue(key);
            if (receivedValues[key] >= value && (writtenOff || _isFrozen(key))) {
                _clearPending(key);
                delete receivedValues[key];
                subAccounts[index] = subAccounts[subAccounts.length - 1];
                subAccounts.pop();
            }
        }
    }

    /// @dev Submits held token-to-redeem inventory through a new request-holder subaccount.
    function _requestRedeem() internal override {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        address subAccount = _createSubAccount();

        subAccounts.push(subAccount);
        _registerPending(uint160(subAccount), amount);
        IERC20(TOKEN_TO_REDEEM).safeTransfer(subAccount, amount);
        ISettlementSubAccount(subAccount).requestRedeem();
    }

    /// @dev Deploys the issuer-specific request-holder subaccount.
    function _createSubAccount() internal virtual returns (address subAccount);

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
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal virtual override {
        super._initialize(initialVersion, initOwner, data);
        __CutoffPricer_init();
    }
}

/// @title SettlementSubAccount
/// @notice Request-holder subaccount for one issuer redemption settlement.
abstract contract SettlementSubAccount is ISettlementSubAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Parent account that owns this subaccount.
    address internal immutable ACCOUNT;
    /// @dev Vault asset expected from settlement.
    address internal immutable ASSET;
    /// @dev Token submitted for redemption.
    address internal immutable TOKEN_TO_REDEEM;

    /* CONSTRUCTOR */

    /// @notice Creates the request-holder subaccount.
    constructor(address asset, address account, address tokenToRedeem) {
        ASSET = asset;
        ACCOUNT = account;
        TOKEN_TO_REDEEM = tokenToRedeem;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc ISettlementSubAccount
    function requestRedeem() external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        _executeRedemption();
    }

    /// @inheritdoc ISettlementSubAccount
    function sync() external returns (uint256 assets, uint256 tokenAmount) {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        assets = IERC20(ASSET).balanceOf(address(this));
        if (assets > 0) {
            IERC20(ASSET).safeTransfer(ACCOUNT, assets);
        }

        tokenAmount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (tokenAmount > 0) {
            IERC20(TOKEN_TO_REDEEM).safeTransfer(ACCOUNT, tokenAmount);
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Submits the held token balance to the issuer's redemption flow.
    function _executeRedemption() internal virtual;
}

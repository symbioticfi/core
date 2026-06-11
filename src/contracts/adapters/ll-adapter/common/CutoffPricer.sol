// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ICutoffPricer} from "../../../../interfaces/adapters/ll-adapter/ICutoffPricer.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title CutoffPricer
/// @notice Mixin pricing pending redemptions against issuer cutoff cohorts.
/// @dev Pending value tracks the live oracle until the cohort pricing date, then freezes at the first
///      oracle price published at/after that date, and is written off after the settlement duration.
///      A zero schedule (rolling mode) assigns each registration its own cohort at registration time.
abstract contract CutoffPricer is ICutoffPricer {
    using SafeCast for uint256;

    /* IMMUTABLES */

    /// @inheritdoc ICutoffPricer
    uint48 public immutable VALUATION_DELAY;
    /// @inheritdoc ICutoffPricer
    uint48 public immutable SETTLEMENT_DURATION;

    /// @dev Initial next-cutoff timestamp applied on initialization (0 for rolling mode).
    uint48 internal immutable INITIAL_CUTOFF;
    /// @dev Initial cutoff period applied on initialization (0 for rolling mode).
    uint48 internal immutable INITIAL_CUTOFF_PERIOD;

    /* STATE VARIABLES */

    /// @inheritdoc ICutoffPricer
    uint48 public cutoff;
    /// @inheritdoc ICutoffPricer
    uint48 public cutoffPeriod;

    /// @inheritdoc ICutoffPricer
    mapping(uint256 key => PendingCohort pendingCohort) public pendingCohorts;

    /* CONSTRUCTOR */

    /// @notice Creates the cutoff pricer.
    constructor(uint48 initialCutoff, uint48 initialCutoffPeriod, uint48 valuationDelay, uint48 settlementDuration) {
        if ((initialCutoff == 0) != (initialCutoffPeriod == 0)) {
            revert InvalidCutoffSchedule();
        }

        INITIAL_CUTOFF = initialCutoff;
        INITIAL_CUTOFF_PERIOD = initialCutoffPeriod;
        VALUATION_DELAY = valuationDelay;
        SETTLEMENT_DURATION = settlementDuration;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Applies the constructor schedule to state. Call once from the host's initializer.
    function __CutoffPricer_init() internal {
        cutoff = INITIAL_CUTOFF;
        cutoffPeriod = INITIAL_CUTOFF_PERIOD;
    }

    /// @dev Updates the cutoff schedule. Hosts expose this behind their owner check.
    function _setCutoffSchedule(uint48 nextCutoff, uint48 period) internal {
        if ((nextCutoff == 0) != (period == 0)) {
            revert InvalidCutoffSchedule();
        }

        cutoff = nextCutoff;
        cutoffPeriod = period;

        emit SetCutoffSchedule(nextCutoff, period);
    }

    /// @dev Tracks a pending redemption under the current cohort.
    function _registerPending(uint256 key, uint256 amount) internal {
        pendingCohorts[key] = PendingCohort({amount: amount.toUint128(), frozenRate: 0, cutoffTimestamp: _rollCutoff()});
    }

    /// @dev Freezes the cohort rate once the pricing date passed and the oracle published at/after it.
    function _tryFreezePending(uint256 key) internal {
        PendingCohort storage pendingCohort = pendingCohorts[key];
        if (pendingCohort.amount == 0 || pendingCohort.frozenRate != 0) {
            return;
        }

        uint256 pricingTimestamp = pendingCohort.cutoffTimestamp + VALUATION_DELAY;
        if (block.timestamp < pricingTimestamp) {
            return;
        }

        (uint256 price, uint48 updatedAt) = _cutoffPriceData();
        if (price != 0 && updatedAt >= pricingTimestamp) {
            pendingCohort.frozenRate = price.toUint128();

            emit FreezePendingCohort(key, price);
        }
    }

    /// @dev Stops tracking a pending redemption.
    function _clearPending(uint256 key) internal {
        delete pendingCohorts[key];
    }

    /// @dev Returns the pending redemption value: live until frozen, frozen until written off.
    function _pendingValue(uint256 key) internal view returns (uint256 assets) {
        PendingCohort storage pendingCohort = pendingCohorts[key];
        uint256 amount = pendingCohort.amount;
        if (amount == 0) {
            return 0;
        }

        uint256 pricingTimestamp = pendingCohort.cutoffTimestamp + VALUATION_DELAY;
        if (block.timestamp >= pricingTimestamp + SETTLEMENT_DURATION) {
            return 0;
        }

        uint256 rate = pendingCohort.frozenRate;
        if (rate == 0) {
            (rate,) = _cutoffPriceData();
            if (rate == 0) {
                revert InvalidCutoffPrice();
            }
        }
        return _cutoffToAssets(amount, rate);
    }

    /// @dev Rolls the stored cutoff to the first cutoff at/after the current time and returns it.
    function _rollCutoff() internal returns (uint48 currentCutoff) {
        currentCutoff = cutoff;
        if (currentCutoff == 0) {
            return uint48(block.timestamp);
        }

        if (block.timestamp > currentCutoff) {
            uint256 period = cutoffPeriod;
            currentCutoff = (currentCutoff + ((block.timestamp - currentCutoff - 1) / period + 1) * period).toUint48();
            cutoff = currentCutoff;
        }
    }

    /// @dev Returns the live oracle price and its last update timestamp.
    function _cutoffPriceData() internal view virtual returns (uint256 price, uint48 updatedAt);

    /// @dev Converts a token-to-redeem amount to vault assets at a rate.
    function _cutoffToAssets(uint256 amount, uint256 rate) internal view virtual returns (uint256 assets);
}

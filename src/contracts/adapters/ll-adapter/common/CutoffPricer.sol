// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ICutoffPricer} from "../../../../interfaces/adapters/ll-adapter/ICutoffPricer.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title CutoffPricer
/// @notice Mixin pricing pending redemptions against issuer cutoff cohorts.
/// @dev Pending value tracks the live oracle until the cohort pricing date, then freezes at the oracle's
///      current price on the first freeze attempt where the oracle's update timestamp is at/after that
///      date (assumes sync is called at least once between the cohort pricing date and the next oracle
///      print for exact cohort pricing), and is written off after the settlement duration.
///      A zero schedule (rolling mode) assigns each registration its own cohort at registration time.
/// @dev State lives in ERC-7201 namespaced storage so hosts inheriting this mixin mid-hierarchy keep
///      their existing storage layouts stable across upgrades.
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

    /* STORAGE */

    /// @custom:storage-location erc7201:symbiotic.storage.CutoffPricer
    struct CutoffPricerStorage {
        uint48 cutoff;
        uint48 cutoffPeriod;
        mapping(uint256 key => PendingCohort pendingCohort) pendingCohorts;
    }

    // keccak256(abi.encode(uint256(keccak256("symbiotic.storage.CutoffPricer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CutoffPricerStorageLocation =
        0x4518cbb92b10961ca7d51fda8b65765d00e8d5eed47c33a9abb9d7b0bf30f100;

    /// @dev Returns cutoff pricer storage at the ERC-7201 namespace.
    function _getCutoffPricerStorage() private pure returns (CutoffPricerStorage storage $) {
        bytes32 location = CutoffPricerStorageLocation;
        assembly {
            $.slot := location
        }
    }

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

    /* VIEW FUNCTIONS */

    /// @inheritdoc ICutoffPricer
    function cutoff() public view returns (uint48 nextCutoff) {
        return _getCutoffPricerStorage().cutoff;
    }

    /// @inheritdoc ICutoffPricer
    function cutoffPeriod() public view returns (uint48 period) {
        return _getCutoffPricerStorage().cutoffPeriod;
    }

    /// @inheritdoc ICutoffPricer
    function pendingCohorts(uint256 key)
        public
        view
        returns (uint128 amount, uint128 frozenRate, uint48 cutoffTimestamp)
    {
        PendingCohort storage pendingCohort = _getCutoffPricerStorage().pendingCohorts[key];
        return (pendingCohort.amount, pendingCohort.frozenRate, pendingCohort.cutoffTimestamp);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Applies the constructor schedule to state. Call once from the host's initializer.
    function __CutoffPricer_init() internal {
        CutoffPricerStorage storage $ = _getCutoffPricerStorage();
        $.cutoff = INITIAL_CUTOFF;
        $.cutoffPeriod = INITIAL_CUTOFF_PERIOD;
    }

    /// @dev Updates the cutoff schedule. Hosts expose this behind their owner check.
    function _setCutoffSchedule(uint48 nextCutoff, uint48 period) internal {
        if ((nextCutoff == 0) != (period == 0)) {
            revert InvalidCutoffSchedule();
        }

        CutoffPricerStorage storage $ = _getCutoffPricerStorage();
        $.cutoff = nextCutoff;
        $.cutoffPeriod = period;

        emit SetCutoffSchedule(nextCutoff, period);
    }

    /// @dev Tracks a pending redemption under the current cohort.
    /// @dev Overwrites any existing entry for `key`; hosts must guarantee key uniqueness across live entries.
    function _registerPending(uint256 key, uint256 amount) internal {
        _getCutoffPricerStorage().pendingCohorts[key] =
            PendingCohort({amount: amount.toUint128(), frozenRate: 0, cutoffTimestamp: _rollCutoff()});
    }

    /// @dev Freezes the cohort rate at the oracle's current price once the pricing date passed and the
    ///      oracle's update timestamp is at/after it. Captures whatever print is live at the first such
    ///      attempt, so sync must run at least once between the pricing date and the next oracle print
    ///      for exact cohort pricing. Skipped once the entry is written off.
    function _tryFreezePending(uint256 key) internal {
        PendingCohort storage pendingCohort = _getCutoffPricerStorage().pendingCohorts[key];
        if (pendingCohort.amount == 0 || pendingCohort.frozenRate != 0) {
            return;
        }

        uint256 pricingTimestamp = pendingCohort.cutoffTimestamp + VALUATION_DELAY;
        if (block.timestamp < pricingTimestamp) {
            return;
        }
        if (block.timestamp >= pricingTimestamp + SETTLEMENT_DURATION) {
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
        delete _getCutoffPricerStorage().pendingCohorts[key];
    }

    /// @dev Returns the pending redemption value: live until frozen, frozen until written off.
    function _pendingValue(uint256 key) internal view returns (uint256 assets) {
        (uint256 value, bool writtenOff) = _cohortValue(key);
        return writtenOff ? 0 : value;
    }

    /// @dev Returns whether a pending entry's cohort rate has been frozen.
    function _isFrozen(uint256 key) internal view returns (bool) {
        return _getCutoffPricerStorage().pendingCohorts[key].frozenRate != 0;
    }

    /// @dev Returns the cohort value at the frozen (or live) rate, and whether the entry is written off.
    function _cohortValue(uint256 key) internal view returns (uint256 value, bool writtenOff) {
        PendingCohort storage pendingCohort = _getCutoffPricerStorage().pendingCohorts[key];
        uint256 amount = pendingCohort.amount;
        if (amount == 0) {
            return (0, false);
        }

        writtenOff = block.timestamp >= pendingCohort.cutoffTimestamp + VALUATION_DELAY + SETTLEMENT_DURATION;

        uint256 rate = pendingCohort.frozenRate;
        if (rate == 0) {
            (rate,) = _cutoffPriceData();
            if (rate == 0) {
                revert InvalidCutoffPrice();
            }
        }
        value = _cutoffToAssets(amount, rate);
    }

    /// @dev Rolls the stored cutoff to the first cutoff at/after the current time and returns it.
    function _rollCutoff() internal returns (uint48 currentCutoff) {
        CutoffPricerStorage storage $ = _getCutoffPricerStorage();
        currentCutoff = $.cutoff;
        if (currentCutoff == 0) {
            return uint48(block.timestamp);
        }

        if (block.timestamp > currentCutoff) {
            uint256 period = $.cutoffPeriod;
            currentCutoff = (currentCutoff + ((block.timestamp - currentCutoff - 1) / period + 1) * period).toUint48();
            $.cutoff = currentCutoff;
        }
    }

    /// @dev Returns the live oracle price and its last update timestamp.
    function _cutoffPriceData() internal view virtual returns (uint256 price, uint48 updatedAt);

    /// @dev Converts a token-to-redeem amount to vault assets at a rate.
    function _cutoffToAssets(uint256 amount, uint256 rate) internal view virtual returns (uint256 assets);
}

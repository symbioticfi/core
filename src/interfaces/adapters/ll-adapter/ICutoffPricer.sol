// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ICutoffPricer
 * @notice Interface for accounts pricing pending redemptions against issuer cutoff cohorts.
 */
interface ICutoffPricer {
    /* ERRORS */

    /**
     * @notice Raised when the live cutoff price is zero.
     */
    error InvalidCutoffPrice();

    /**
     * @notice Raised when a cutoff schedule is partially zero.
     */
    error InvalidCutoffSchedule();

    /* EVENTS */

    /**
     * @notice Emitted when the cutoff schedule is updated.
     * @param nextCutoff The next cutoff timestamp (0 for rolling mode).
     * @param period The cutoff period (0 for rolling mode).
     */
    event SetCutoffSchedule(uint48 nextCutoff, uint48 period);

    /**
     * @notice Emitted when a pending cohort's rate is frozen.
     * @param key The pending redemption key.
     * @param rate The frozen rate in the host's oracle rate precision.
     */
    event FreezePendingCohort(uint256 indexed key, uint256 rate);

    /* STRUCTS */

    /**
     * @notice Pending redemption tracked against a cutoff cohort.
     * @param amount The token-to-redeem amount pending.
     * @param frozenRate The oracle price captured on the first freeze attempt at/after the pricing date
     *        (0 until frozen). Assumes sync is called at least once between the cohort pricing date and
     *        the next oracle print for exact cohort pricing.
     * @param cutoffTimestamp The cohort cutoff timestamp assigned at registration.
     */
    struct PendingCohort {
        uint128 amount;
        uint128 frozenRate;
        uint48 cutoffTimestamp;
    }

    /* FUNCTIONS */

    /**
     * @notice Returns the delay between a cutoff and its cohort pricing date.
     * @return valuationDelay The valuation delay.
     */
    function VALUATION_DELAY() external view returns (uint48 valuationDelay);

    /**
     * @notice Returns how long after the pricing date pending value is counted.
     * @return settlementDuration The settlement duration.
     */
    function SETTLEMENT_DURATION() external view returns (uint48 settlementDuration);

    /**
     * @notice Returns the next cutoff timestamp (0 for rolling mode).
     * @return nextCutoff The next cutoff timestamp.
     */
    function cutoff() external view returns (uint48 nextCutoff);

    /**
     * @notice Returns the cutoff period (0 for rolling mode).
     * @return period The cutoff period.
     */
    function cutoffPeriod() external view returns (uint48 period);

    /**
     * @notice Returns a tracked pending cohort entry.
     * @param key The pending redemption key.
     * @return amount The token-to-redeem amount pending.
     * @return frozenRate The frozen cohort rate (0 until frozen).
     * @return cutoffTimestamp The assigned cohort cutoff timestamp.
     */
    function pendingCohorts(uint256 key)
        external
        view
        returns (uint128 amount, uint128 frozenRate, uint48 cutoffTimestamp);
}

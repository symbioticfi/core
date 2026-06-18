// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "./ICooldownAccount.sol";
import {ICutoffAccount} from "./ICutoffAccount.sol";

/**
 * @title ISettlementAccount
 * @notice Interface for liquidity lane accounts settling redemptions through request-holder subaccounts.
 */
interface ISettlementAccount is ICooldownAccount, ICutoffAccount {
    /* ERRORS */

    /**
     * @notice Raised when migrating an account that still tracks live subaccounts.
     */
    error MigrationWithLiveSubAccounts();

    /**
     * @notice Raised when rescuing a subaccount that is still tracked for settlement.
     */
    error SubAccountTracked();

    /**
     * @notice Raised when rescuing an address never created as a subaccount of this account.
     */
    error UnknownSubAccount();

    /* EVENTS */

    /**
     * @notice Emitted when a cutoff bucket's rate is frozen.
     * @param bucket The bucket index.
     * @param rate The frozen rate in the host's oracle precision.
     */
    event FreezeBucket(uint48 indexed bucket, uint256 rate);

    /**
     * @notice Emitted when a subaccount balance is swept.
     * @param subAccount The swept subaccount.
     * @param assets The vault-asset amount swept.
     * @param tokenAmount The token-to-redeem amount swept.
     */
    event SweepSubAccount(address indexed subAccount, uint256 assets, uint256 tokenAmount);

    /**
     * @notice Emitted when a subaccount is released from active tracking.
     * @param subAccount The released subaccount.
     */
    event ReleaseSubAccount(address indexed subAccount);

    /* FUNCTIONS */

    /**
     * @notice Returns the delay between a cutoff and its pricing date.
     * @return valuationDelay The valuation delay.
     */
    function VALUATION_DELAY() external view returns (uint48 valuationDelay);

    /**
     * @notice Returns how long after the cutoff pending value is counted.
     * @return postCutoffWindow The post-cutoff window.
     */
    function POST_CUTOFF_WINDOW() external view returns (uint48 postCutoffWindow);

    /**
     * @notice Returns a cutoff bucket.
     * @param bucket The bucket index.
     * @return totalTokenToRedeem The cumulative token-to-redeem amount submitted to this bucket.
     * @return pendingTokenToRedeem The still-pending token-to-redeem amount in this bucket.
     * @return rate The frozen bucket rate.
     */
    function buckets(uint48 bucket)
        external
        view
        returns (uint256 totalTokenToRedeem, uint256 pendingTokenToRedeem, uint256 rate);

    /**
     * @notice Returns a pending cutoff entry by key.
     * @param key The pending redemption key.
     * @return amount The token-to-redeem amount pending.
     * @return bucket The assigned cutoff bucket index.
     */
    function pendingCutoffs(uint256 key) external view returns (uint256 amount, uint48 bucket);

    /**
     * @notice Returns a redemption-request subaccount by index.
     * @param index The subaccount index.
     * @return subAccount The subaccount address.
     */
    function subAccounts(uint256 index) external view returns (address subAccount);

    /**
     * @notice Returns whether an address was ever created as a subaccount of this account.
     * @param subAccount The address to check.
     * @return created Whether the address is a subaccount created by this account.
     */
    function isSubAccount(address subAccount) external view returns (bool created);

    /**
     * @notice Sweeps a late settlement that arrived on an already-released subaccount. Permissionless:
     *         swept funds become plain account balance, so there is nothing to grief.
     * @param subAccount The released subaccount to sweep.
     */
    function rescueSubAccount(address subAccount) external;
}

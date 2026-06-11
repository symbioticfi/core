// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "./ICooldownAccount.sol";
import {ICutoffPricer} from "./ICutoffPricer.sol";

/**
 * @title ISettlementAccount
 * @notice Interface for liquidity lane accounts settling redemptions through request-holder subaccounts.
 */
interface ISettlementAccount is ICooldownAccount, ICutoffPricer {
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
     * @notice Emitted when a subaccount sweep credits settlement value.
     * @param subAccount The swept subaccount.
     * @param assets The vault-asset amount swept.
     * @param tokenAmount The token-to-redeem amount swept.
     */
    event SweepSubAccount(address indexed subAccount, uint256 assets, uint256 tokenAmount);

    /**
     * @notice Emitted when a value-covered subaccount is released.
     * @param subAccount The released subaccount.
     */
    event ReleaseSubAccount(address indexed subAccount);

    /* FUNCTIONS */

    /**
     * @notice Returns a redemption-request subaccount by index.
     * @param index The subaccount index.
     * @return subAccount The subaccount address.
     */
    function subAccounts(uint256 index) external view returns (address subAccount);

    /**
     * @notice Returns the cumulative settlement value received for a subaccount key, in vault assets.
     * @param key The subaccount key (`uint160(subAccount)`).
     * @return assets The cumulative received vault-asset value.
     */
    function receivedValues(uint256 key) external view returns (uint256 assets);

    /**
     * @notice Returns whether an address was ever created as a subaccount of this account.
     * @param subAccount The address to check.
     * @return created Whether the address is a subaccount created by this account.
     */
    function isSubAccount(address subAccount) external view returns (bool created);

    /**
     * @notice Updates the cutoff schedule. Only callable by the owner.
     * @param nextCutoff The next cutoff timestamp (0 for rolling mode).
     * @param period The cutoff period (0 for rolling mode).
     */
    function setCutoffSchedule(uint48 nextCutoff, uint48 period) external;

    /**
     * @notice Sweeps a late settlement that arrived on an already-released subaccount. Permissionless:
     *         swept funds become plain account balance, so there is nothing to grief.
     * @param subAccount The released subaccount to sweep.
     */
    function rescueSubAccount(address subAccount) external;
}

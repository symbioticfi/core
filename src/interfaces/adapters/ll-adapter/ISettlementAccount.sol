// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "./ICooldownAccount.sol";
import {ICutoffPricer} from "./ICutoffPricer.sol";

/**
 * @title ISettlementAccount
 * @notice Interface for liquidity lane accounts settling redemptions through request-holder subaccounts.
 */
interface ISettlementAccount is ICooldownAccount, ICutoffPricer {
    /* FUNCTIONS */

    /**
     * @notice Returns a redemption-request subaccount by index.
     * @param index The subaccount index.
     * @return subAccount The subaccount address.
     */
    function subAccounts(uint256 index) external view returns (address subAccount);

    /**
     * @notice Updates the cutoff schedule. Only callable by the owner.
     * @param nextCutoff The next cutoff timestamp (0 for rolling mode).
     * @param period The cutoff period (0 for rolling mode).
     */
    function setCutoffSchedule(uint48 nextCutoff, uint48 period) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/**
 * @title ISecuritizeAccount
 * @notice Interface for Securitize liquidity lane accounts.
 */
interface ISecuritizeAccount is ICooldownAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns how long pending assets are counted in valuation.
     * @return pendingAssetsDuration The pending-assets valuation duration.
     */
    function PENDING_ASSETS_DURATION() external view returns (uint48 pendingAssetsDuration);

    /**
     * @notice Returns a Securitize redemption-request subaccount by index.
     * @param index The subaccount index.
     * @return subAccount The subaccount address.
     */
    function subAccounts(uint256 index) external view returns (address subAccount);
}

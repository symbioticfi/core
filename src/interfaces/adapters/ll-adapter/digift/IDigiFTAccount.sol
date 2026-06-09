// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "../IAccount.sol";

/**
 * @title IDigiFTAccount
 * @notice Interface for DigiFT liquidity lane accounts.
 */
interface IDigiFTAccount is IAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns how long DigiFT pending assets are counted in valuation.
     * @return pendingAssetsDuration The pending-assets valuation duration.
     */
    function PENDING_ASSETS_DURATION() external view returns (uint48 pendingAssetsDuration);

    /**
     * @notice Returns the DigiFT normal redemption manager.
     * @return subRedManagement The redemption manager address.
     */
    function SUB_RED_MANAGEMENT() external view returns (address subRedManagement);

    /**
     * @notice Returns a DigiFT redemption-request subaccount by index.
     * @param index The subaccount index.
     * @return subAccount The subaccount address.
     */
    function subAccounts(uint256 index) external view returns (address subAccount);
}

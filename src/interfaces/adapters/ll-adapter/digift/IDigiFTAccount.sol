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
     * @notice Returns the wallet receiving DigiFT redemption transfers.
     * @return wallet The redemption wallet address.
     */
    function REDEMPTION_WALLET() external view returns (address wallet);

    /**
     * @notice Returns how long pending off-chain redemption assets remain counted.
     * @return duration The pending assets duration.
     */
    function PENDING_ASSETS_DURATION() external view returns (uint48 duration);

    /**
     * @notice Returns a DigiFT redemption-request subaccount by index.
     * @param index The subaccount index.
     * @return subAccount The subaccount address.
     */
    function subAccounts(uint256 index) external view returns (address subAccount);
}

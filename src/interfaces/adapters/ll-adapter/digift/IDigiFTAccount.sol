// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISettlementAccount} from "../ISettlementAccount.sol";

/**
 * @title IDigiFTAccount
 * @notice Interface for DigiFT liquidity lane accounts.
 */
interface IDigiFTAccount is ISettlementAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the DigiFT normal redemption manager.
     * @return subRedManagement The redemption manager address.
     */
    function SUB_RED_MANAGEMENT() external view returns (address subRedManagement);
}

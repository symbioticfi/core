// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/**
 * @title IFigureAccount
 * @notice Interface for Figure/Hastra liquidity lane accounts.
 */
interface IFigureAccount is ICooldownAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns a Figure request-holder subaccount by index.
     * @param index The subaccount index.
     * @return subAccount The subaccount address.
     */
    function subAccounts(uint256 index) external view returns (address subAccount);
}

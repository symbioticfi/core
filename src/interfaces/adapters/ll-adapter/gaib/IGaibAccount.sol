// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/**
 * @title IGaibAccount
 * @notice Interface for GAIB liquidity lane accounts.
 */
interface IGaibAccount is ICooldownAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns a GAIB request-holder subaccount by index.
     * @param index The subaccount index.
     * @return subAccount The subaccount address.
     */
    function subAccounts(uint256 index) external view returns (address subAccount);
}

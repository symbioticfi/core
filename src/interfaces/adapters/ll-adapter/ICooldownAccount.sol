// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "./IAccount.sol";

/**
 * @title ICooldownAccount
 * @notice Interface for liquidity lane accounts with cooldown-gated requests.
 */
interface ICooldownAccount is IAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the minimum delay between requests for non-owner callers.
     * @return cooldown The cooldown duration.
     */
    function COOLDOWN() external view returns (uint48 cooldown);

    /**
     * @notice Returns the timestamp of the latest request.
     * @return time The latest request timestamp.
     */
    function lastRequestTimestamp() external view returns (uint48 time);
}

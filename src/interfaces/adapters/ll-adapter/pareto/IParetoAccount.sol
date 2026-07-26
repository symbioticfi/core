// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "../IAccount.sol";

/**
 * @title IParetoAccount
 * @notice Interface for Pareto queue-based liquidity lane accounts.
 */
interface IParetoAccount is IAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the Pareto epoch withdrawal queue.
     * @return withdrawalQueue The queue address.
     */
    function WITHDRAWAL_QUEUE() external view returns (address withdrawalQueue);

    /**
     * @notice Returns the token paid out by Pareto redemptions (the queue underlying).
     * @return redemptionToken The redemption-token address.
     */
    function REDEMPTION_TOKEN() external view returns (address redemptionToken);

    /**
     * @notice Returns a tracked queue processing epoch.
     * @param index The tracked-epoch index.
     * @return epoch The queue processing epoch.
     */
    function queueEpochs(uint256 index) external view returns (uint256 epoch);
}

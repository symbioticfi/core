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
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISettlementAccount} from "../ISettlementAccount.sol";

/**
 * @title ISecuritizeAccount
 * @notice Interface for Securitize liquidity lane accounts.
 */
interface ISecuritizeAccount is ISettlementAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the Securitize redemption wallet receiving redemption notices.
     * @return redemptionWallet The redemption wallet address.
     */
    function REDEMPTION_WALLET() external view returns (address redemptionWallet);
}

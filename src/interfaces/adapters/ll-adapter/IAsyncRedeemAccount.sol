// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "./ICooldownAccount.sol";

/**
 * @title IAsyncRedeemAccount
 * @notice Interface for liquidity lane accounts that redeem through ERC-7540 async redeem vaults.
 */
interface IAsyncRedeemAccount is ICooldownAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns an ERC-7540 redemption request id by index.
     * @param index The request index.
     * @return requestId The redemption request id.
     */
    function requestIds(uint256 index) external view returns (uint64 requestId);
}

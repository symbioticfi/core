// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "../IAccount.sol";

/**
 * @title IPikuFundingManagerAccount
 * @notice Interface for Piku funding manager liquidity lane accounts.
 */
interface IPikuFundingManagerAccount is IAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the Piku funding manager used for queued redemption requests.
     * @return manager The funding manager address.
     */
    function FUNDING_MANAGER() external view returns (address manager);

    /**
     * @notice Returns requested value no longer held as Piku tokens.
     * @return assets The pending vault-asset value.
     */
    function pendingAssets() external view returns (uint256 assets);
}

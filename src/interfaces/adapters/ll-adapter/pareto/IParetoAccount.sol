// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/**
 * @title IParetoAccount
 * @notice Interface for Pareto liquidity lane accounts.
 */
interface IParetoAccount is ICooldownAccount {
    /* ERRORS */

    /**
     * @notice Raised when the Pareto underlying token is not the vault asset.
     */
    error InvalidAsset();

    /* FUNCTIONS */

    /**
     * @notice Returns the Pareto credit vault.
     * @return idleCdo The Pareto credit vault address.
     */
    function IDLE_CDO() external view returns (address idleCdo);

    /**
     * @notice Returns the Pareto withdrawal receipt token.
     * @return receiptToken The receipt token address.
     */
    function RECEIPT_TOKEN() external view returns (address receiptToken);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "../IAccount.sol";

/**
 * @title IThreeJaneAccount
 * @notice Interface for 3Jane liquidity lane accounts.
 */
interface IThreeJaneAccount is IAccount {
    /* ERRORS */

    /**
     * @notice Raised when the 3Jane withdrawal asset is not the vault asset.
     */
    error InvalidAsset();
}

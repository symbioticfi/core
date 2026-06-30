// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "./IAccount.sol";

/**
 * @title IERC4626Account
 * @notice Interface for ERC-4626 liquidity lane accounts.
 */
interface IERC4626Account is IAccount {
    /* ERRORS */

    /**
     * @notice Raised when the ERC-4626 vault asset is not the vault asset.
     */
    error InvalidAsset();
}
